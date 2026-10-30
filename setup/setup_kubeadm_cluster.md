# Créer un cluster Kubernetes avec kubeadm

Ce guide décrit l'installation d'un cluster Kubernetes sur des serveurs **Ubuntu Server 24.04 LTS ou ultérieur**, à l'aide de `kubeadm`, `containerd` et Calico. Il ne dépend pas d'un fournisseur cloud ou d'un outil de virtualisation particulier.

La configuration minimale comprend **un control plane et un worker**. Ajouter des workers revient à répéter les étapes de préparation et de jonction. Ce guide configure un control plane : ajouter plusieurs control planes demande aussi un endpoint d'API stable et une configuration haute disponibilité adaptée.

Les commandes avec `sudo` sont à exécuter sur les serveurs concernés. Les commandes `kubectl` après l'initialisation sont à exécuter sur le control plane, ou sur une machine d'administration configurée avec son kubeconfig.

## 1. Nommer les serveurs

Attribuer un hostname unique à chaque serveur **avant d'installer Kubernetes**. Utiliser des noms simples, en minuscules, sans espaces, par exemple `k8s-controlplane` pour le control plane et `k8s-node01` pour un worker. Pour les workers supplémentaires, utiliser `k8s-node02`, `k8s-node03`, etc.

Exécuter la commande correspondante sur chaque serveur :

```bash
# Sur le control plane
sudo hostnamectl set-hostname k8s-controlplane

# Sur le premier worker (à exécuter sur le worker, pas sur le control plane)
sudo hostnamectl set-hostname k8s-node01
```

Le nom est appliqué immédiatement. Vérifier le résultat sur chaque serveur :

```bash
hostnamectl
hostname
```

Chaque nœud doit avoir un hostname distinct. Si les noms choisis ne sont pas résolus par le DNS local, les workers peuvent tout de même joindre le control plane avec son adresse IP privée stable, utilisée dans les étapes suivantes.

## 2. Préparer les serveurs

Avant de commencer :

- installer Ubuntu Server 24.04 LTS ou une version ultérieure prise en charge sur chaque serveur ;
- attribuer un nom distinct et une adresse IP privée stable à chaque serveur ;
- vérifier que le control plane et les workers peuvent communiquer entre eux et accéder aux dépôts de paquets et aux images de conteneurs ;
- synchroniser l'horloge des serveurs ;
- réserver suffisamment de CPU, mémoire et espace disque pour le système, Kubernetes et les workloads. Les besoins dépendent des applications ; un cluster de production nécessite davantage de ressources qu'un cluster de test.

Au minimum, rendre l'API du control plane accessible aux workers et aux machines d'administration autorisées sur TCP/6443 et permettre la communication nécessaire entre les nœuds. Les ports supplémentaires dépendent des composants utilisés :

- kubelet : TCP/10250 entre le control plane et les nœuds ;
- etcd : TCP/2379-2380 entre les control planes si le cluster en comporte plusieurs ;
- réseau des pods : selon le CNI choisi. Par exemple, Calico peut nécessiter UDP/4789 en mode VXLAN ou TCP/179 en mode BGP ;
- NodePort : TCP/30000-32767 uniquement si cette méthode d'exposition est utilisée.

Adapter les règles de pare-feu au CNI et aux besoins réels. Ne pas exposer l'API Kubernetes ou etcd à Internet.

Vérifier sur chaque serveur son système, son nom et ses adresses :

```bash
cat /etc/os-release
hostnamectl
ip -br address
```

Noter l'adresse privée stable du control plane ; elle sera utilisée lors de l'initialisation et par les workers pour joindre l'API.

## 3. Préparer tous les nœuds

Répéter cette section sur **le control plane et chaque worker**.

### 3.1 Désactiver le swap et configurer le noyau

Kubernetes doit pouvoir gérer la mémoire des pods de façon prévisible. Vérifier si le swap est actif, puis le désactiver :

```bash
swapon --show
sudo swapoff -a
```

Si une entrée de swap figure dans `/etc/fstab`, la commenter avec `sudoedit /etc/fstab` pour éviter sa réactivation au prochain démarrage.

Charger les modules réseau requis :

```bash
cat <<'EOF' | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
```

Activer le routage IPv4 et le traitement du trafic transféré :

```bash
cat <<'EOF' | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
```

Vérifier :

```bash
lsmod | grep -E 'overlay|br_netfilter'
sysctl net.ipv4.ip_forward
```

La dernière commande doit afficher `net.ipv4.ip_forward = 1`.

### 3.2 Installer et configurer `containerd`

Installer `containerd` depuis le dépôt officiel Docker pour Ubuntu :

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt-get update
sudo apt-get install -y containerd.io
```

Configurer `containerd` pour utiliser le pilote cgroup `systemd`, cohérent avec celui de `kubelet` :

```bash
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' \
  /etc/containerd/config.toml
sudo systemctl enable --now containerd
sudo systemctl restart containerd
```

Vérifier le service et la configuration active :

```bash
systemctl is-active containerd
sudo containerd config dump | grep -E 'SystemdCgroup|disabled_plugins'
```

Le service doit être `active`, `SystemdCgroup` doit être à `true` et le plugin CRI ne doit pas être désactivé. Si la configuration générée ne contient pas le réglage attendu, vérifier le chemin de configuration fourni par la version installée de `containerd` et corriger le fichier avant de continuer.

### 3.3 Installer `kubelet`, `kubeadm` et `kubectl`

Choisir une version Kubernetes encore prise en charge et installer **la même version mineure sur tous les nœuds**. L'exemple utilise `v1.37` ; vérifier les versions disponibles et les instructions à jour dans la [documentation officielle kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/).

Configurer le dépôt pour cette version :

```bash
K8S_MINOR=v1.37
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
sudo install -m 0755 -d /etc/apt/keyrings

curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key" \
  | sudo gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable --now kubelet
```

Répéter avec la même valeur de `K8S_MINOR` partout. Vérifier les outils :

```bash
kubeadm version -o short
kubectl version --client
systemctl is-active containerd
```

Avant l'initialisation ou la jonction au cluster, `kubelet` peut redémarrer en boucle : il attend sa configuration et cela est normal.

## 4. Initialiser le control plane

Exécuter cette étape **une seule fois**, sur le serveur qui sera le control plane. Choisir un réseau de pods qui ne chevauche ni le réseau des serveurs ni celui des services. L'exemple utilise `10.244.0.0/16` ; le CNI de l'étape suivante doit être configuré avec le même CIDR.

Remplacer `ADRESSE_PRIVEE_DU_CONTROL_PLANE` par l'adresse privée stable relevée à l'étape 2 :

```bash
sudo kubeadm init \
  --apiserver-advertise-address=ADRESSE_PRIVEE_DU_CONTROL_PLANE \
  --pod-network-cidr=10.244.0.0/16
```

Si l'initialisation réussit, `kubeadm` affiche une commande `kubeadm join` avec un token et une empreinte de certificat. La conserver pour l'étape 6. Si elle expire, générer une nouvelle commande sur le control plane :

```bash
sudo kubeadm token create --print-join-command
```

Configurer `kubectl` pour l'utilisateur courant du control plane :

```bash
mkdir -p "$HOME/.kube"
sudo cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
kubectl get nodes
```

Le nœud peut être `NotReady` tant que le plugin réseau (CNI) n'est pas installé.

## 5. Installer le réseau des pods (CNI)

Kubernetes a besoin d'un CNI pour le réseau des pods. Ce guide prend Calico comme exemple ; utiliser une version compatible avec la version de Kubernetes installée et suivre la [documentation officielle d'installation de Calico](https://docs.tigera.io/calico/latest/getting-started/kubernetes/).

Télécharger le manifeste versionné. Vérifier la compatibilité de la version Calico avant de l'appliquer :

```bash
CALICO_VERSION=v3.31.2
curl -fsSLo calico.yaml \
  "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml"
```

Dans `calico.yaml`, configurer `CALICO_IPV4POOL_CIDR` à `10.244.0.0/16` pour faire correspondre le réseau Calico à la valeur de `--pod-network-cidr` utilisée à l'étape 4. Appliquer le manifeste depuis le control plane :

```bash
kubectl apply -f calico.yaml
kubectl get pods --namespace kube-system --watch
```

Attendre que les composants réseau soient prêts, puis arrêter le suivi avec `Ctrl+C` et vérifier :

```bash
kubectl get nodes -o wide
kubectl get pods --namespace kube-system -o wide
```

Le control plane doit passer à `Ready`.

## 6. Joindre au moins un worker

Répéter cette étape sur **chaque worker**, après l'avoir préparé à l'étape 3. Exécuter avec `sudo` la commande `kubeadm join` conservée à l'étape 4. Elle a cette forme :

```bash
sudo kubeadm join ADRESSE_PRIVEE_DU_CONTROL_PLANE:6443 \
  --token TOKEN \
  --discovery-token-ca-cert-hash sha256:EMPREINTE
```

Utiliser la commande complète affichée par `kubeadm init` ou `kubeadm token create --print-join-command`, sans inventer ni réutiliser les valeurs d'exemple.

Sur le control plane, vérifier l'arrivée des nœuds :

```bash
kubectl get nodes -o wide
```

Le control plane et au moins un worker doivent apparaître `Ready`. Ajouter d'autres workers en répétant la préparation et la commande `kubeadm join`.

## 7. Vérifier le cluster

Créer un déploiement temporaire pour vérifier que les workloads sont planifiés :

```bash
kubectl create deployment nginx --image=nginx --replicas=2
kubectl rollout status deployment/nginx --timeout=180s
kubectl get pods -o wide
```

Vérifier que les deux pods sont `Running`. Avec un control plane kubeadm standard, les workloads sont normalement planifiés sur le ou les workers, car le control plane est protégé par une taint.

Nettoyer le déploiement de test :

```bash
kubectl delete deployment nginx
```

État général du cluster :

```bash
kubectl get nodes
kubectl get pods --all-namespaces
kubectl get events --all-namespaces --sort-by=.lastTimestamp
```

## 8. Choisir une solution de stockage (optionnel)

Un cluster peut démarrer sans `StorageClass`. Une application qui demande un PVC a toutefois besoin d'une StorageClass et d'un provisionneur compatibles. Choisir une solution selon les besoins :

- **Stockage local simple** : suivre le [guide d'installation de local-path](./local-path-storage-class.md). C'est une option simple pour un lab ; les données résident sur un seul nœud, sans réplication ni bascule automatique.
- **Stockage réseau ou distribué** : installer un système adapté à l'infrastructure et aux objectifs de disponibilité. Vérifier les prérequis, la compatibilité et la procédure de sauvegarde propres à cette solution.

Une StorageClass peut être définie par défaut ou sélectionnée explicitement dans le PVC avec `storageClassName`. Ne pas supposer qu'une classe existe déjà :

```bash
kubectl get storageclass
```

## 9. Publier des applications (optionnel)

Pour accéder aux applications depuis l'extérieur du cluster, choisir une méthode adaptée à l'environnement :

- **MetalLB** peut fournir des adresses `LoadBalancer` sur un cluster qui ne dispose pas d'intégration native avec un fournisseur de load balancer. Il faut réserver une plage d'adresses compatible avec le réseau des nœuds.
- **Traefik** peut recevoir le trafic HTTP/HTTPS et le router vers les applications au moyen d'Ingress.

Le dépôt contient le [guide MetalLB et Traefik](./metalb-traefik.md), avec les procédures d'installation et de configuration. Son exemple réseau est adapté à Lightsail : pour un autre environnement, remplacer les adresses et règles de pare-feu par celles de son propre réseau. Dans un cloud qui fournit déjà un load balancer Kubernetes, il peut être préférable d'utiliser cette intégration plutôt que MetalLB.

## Dépannage

### `kubeadm init` échoue aux contrôles préalables

Vérifier que le swap est désactivé, que `net.ipv4.ip_forward` vaut `1`, que `containerd` est actif et que les outils Kubernetes sont installés avec la même version mineure.

```bash
swapon --show
sysctl net.ipv4.ip_forward
systemctl status containerd
sudo journalctl -u kubelet --since=10m
```

### Un nœud reste `NotReady`

Vérifier que le CNI est installé et opérationnel, et que son CIDR correspond à celui de `kubeadm init` :

```bash
kubectl get pods --namespace kube-system -o wide
kubectl describe node NOM_DU_NOEUD
kubectl get events --all-namespaces --sort-by=.lastTimestamp
```

### Un worker ne rejoint pas le cluster

Vérifier la connectivité du worker vers l'adresse stable du control plane sur TCP/6443, l'horloge, et les paramètres de la commande `kubeadm join`. Si le token a expiré, en générer un nouveau sur le control plane avec `sudo kubeadm token create --print-join-command`.

### Des pods ne peuvent pas communiquer entre eux

Vérifier les pods et journaux du CNI, les règles de pare-feu entre nœuds et l'absence de chevauchement entre le CIDR des pods, le réseau des serveurs et le CIDR des Services Kubernetes.

## Résultat attendu

- Au moins un control plane et un worker sont `Ready`.
- Le CNI et les composants système sont opérationnels.
- Le déploiement de test a démarré puis a été supprimé.
- Le stockage et l'exposition externe ne sont installés que si le cluster en a besoin.
