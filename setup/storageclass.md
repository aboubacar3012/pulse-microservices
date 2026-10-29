# Installer Longhorn et configurer le stockage Kubernetes

Ce guide installe Longhorn sur un cluster kubeadm avec Helm, configure le `StorageClass` `longhorn` comme classe par défaut et vérifie le provisionnement d'un volume.

Longhorn est un stockage distribué : il conserve des réplicas des volumes sur les disques locaux des nœuds. Ce n'est pas une sauvegarde. Prévoir des sauvegardes séparées et tester leur restauration.

Pour comprendre l'architecture et les limites de ressources choisies dans cette configuration, consulter [`longhorn.md`](./longhorn.md).

Sauf mention contraire, exécuter les commandes `kubectl` et Helm depuis la racine du dépôt, avec le contexte `kubectl` pointant vers le cluster cible et un compte autorisé à installer des composants cluster-wide.

## 1. Vérifier la compatibilité et les prérequis

La configuration de ce dépôt épingle Longhorn **1.13.0**, dont le chart exige Kubernetes **1.34 ou supérieur**. Vérifier la version serveur :

```bash
kubectl version
```

Si le cluster est plus ancien, ne pas installer cette version. Choisir une version Longhorn encore maintenue et compatible avec la version Kubernetes du cluster, puis modifier `--version` dans les commandes ci-dessous.

Les autres prérequis doivent être satisfaits sur **chaque nœud qui hébergera des réplicas Longhorn** :

- Un CNI fonctionnel, des nœuds Linux et `mountPropagation` activé.
- Les commandes système `bash`, `curl`, `findmnt`, `grep`, `awk`, `blkid` et `lsblk`.
- Longhorn s'exécute avec des permissions privilégiées et doit pouvoir accéder aux ressources système des hôtes.
- Installer Longhorn uniquement sur un cluster dont vous administrez et contrôlez les nœuds; ses composants privilégiés ont accès aux ressources système des hôtes.
- Pour le moteur V1 utilisé par défaut, `open-iscsi` doit être installé et le service `iscsid` actif.
- Pour les volumes RWX et les sauvegardes NFS, installer aussi le client NFSv4 (`nfs-common` sur Ubuntu/Debian).

Sur chaque nœud Ubuntu/Debian, installer les dépendances :

```bash
sudo apt-get update
sudo apt-get install -y open-iscsi nfs-common
sudo systemctl enable --now iscsid
sudo modprobe iscsi_tcp
```

Vérifier sur chaque nœud :

```bash
systemctl is-active iscsid
iscsiadm --version
lsmod | grep iscsi_tcp
```

Longhorn signale une incompatibilité critique avec `open-iscsi` **2.1.12** : ne pas installer cette version. Utiliser une version <= 2.1.11 ou >= 2.1.13.

Documentation complète : [prérequis d'installation Longhorn](https://longhorn.io/docs/1.13.0/deploy/install/).

## 2. Préparer l'espace disque sur les nœuds de stockage

La configuration Helm de ce dépôt crée les disques Longhorn uniquement sur les nœuds portant le label `node.longhorn.io/create-default-disk=true`. Elle utilise le chemin `/var/lib/longhorn`.

Avant de poser le label sur un nœud :

1. Prévoir un disque ou un système de fichiers persistant avec suffisamment d'espace.
2. Le monter durablement sur `/var/lib/longhorn` (par exemple avec `/etc/fstab` ou la configuration de stockage de l'hébergeur).
3. Vérifier le montage et l'espace disponible :

```bash
findmnt -T /var/lib/longhorn
df -h /var/lib/longhorn
```

Ne pas poser le label tant que le chemin n'est pas sur le stockage prévu. Sinon, Longhorn peut écrire sur la partition système du nœud. Répéter ces vérifications pour chaque nœud de stockage, puis appliquer le label depuis une machine ayant accès au cluster :

```bash
kubectl label node <NOM_DU_NOEUD> node.longhorn.io/create-default-disk=true
```

Répéter la commande en remplaçant le nom du nœud pour chaque nœud éligible. Pour choisir un autre chemin, modifier `defaultSettings.defaultDataPath` dans [`values.yaml`](./longhorn/values.yaml) et monter le disque à ce chemin sur chacun des nœuds concernés.

## 3. Installer Longhorn avec Helm

Le fichier [`setup/longhorn/values.yaml`](./longhorn/values.yaml) :

- crée la classe de stockage `longhorn` et la marque comme StorageClass par défaut ;
- configure trois réplicas par volume ;
- limite la création automatique des disques aux nœuds explicitement labellisés ;
- place les données dans `/var/lib/longhorn` ;
- configure des requests et limites CPU/mémoire pour Longhorn Manager et Longhorn Global Manager ;
- limite la surallocation de capacité disque à 100 % et conserve 25 % d'espace disponible comme seuil minimal.

Trois réplicas nécessitent au moins trois nœuds de stockage éligibles et consomment environ trois fois la taille logique des volumes. Pour un cluster de lab à un seul nœud, régler `persistence.defaultClassReplicaCount` à `1` avant l'installation : les données ne seront alors pas protégées contre la panne de ce nœud. Avec deux nœuds, utiliser `2`.

Ajouter le dépôt et installer la version épinglée :

```bash
helm repo add longhorn https://charts.longhorn.io
helm repo update
helm upgrade --install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace \
  --version 1.13.0 \
  --values setup/longhorn/values.yaml
```

Attendre que les composants soient prêts :

```bash
kubectl rollout status deployment/longhorn-driver-deployer \
  --namespace longhorn-system \
  --timeout=300s
kubectl get pods --namespace longhorn-system
```

Vérifier le StorageClass et les nœuds reconnus par Longhorn :

```bash
kubectl get storageclass
kubectl get nodes.longhorn.io --namespace longhorn-system
```

Le StorageClass `longhorn` doit être indiqué comme classe par défaut. Vérifier dans l'interface Longhorn que les nœuds et leurs disques sont sains et disposent de l'espace prévu.

> **StorageClass par défaut existant :** Kubernetes peut avoir plusieurs classes portant l'annotation `storageclass.kubernetes.io/is-default-class=true`, mais les PVC sans `storageClassName` peuvent alors être ambigus. Avant l'installation, vérifiez `kubectl get storageclass` et décidez explicitement si Longhorn doit remplacer l'actuelle classe par défaut.

## 4. Tester un PVC

Créer un PVC qui sélectionne explicitement Longhorn et un pod qui écrit un fichier :

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: longhorn-test
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: longhorn-test
  namespace: default
spec:
  containers:
    - name: test
      image: busybox:1.36
      command: ["sh", "-c", "echo longhorn-ok > /data/check.txt && cat /data/check.txt && sleep 3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: longhorn-test
EOF
```

Vérifier que le PVC est `Bound`, que le pod est prêt et que le fichier est présent :

```bash
kubectl get pvc longhorn-test --namespace default
kubectl get pod longhorn-test --namespace default
kubectl logs longhorn-test --namespace default
```

Les journaux doivent afficher `longhorn-ok`. Une fois le test terminé, supprimer le pod et le PVC de test :

```bash
kubectl delete pod longhorn-test --namespace default
kubectl delete pvc longhorn-test --namespace default
```

Cette suppression détruit le volume de test conformément à la politique de rétention par défaut. Ne pas appliquer ces commandes à un PVC de production.

## Accéder à l'interface Longhorn

L'interface n'active pas l'authentification par défaut. Ne l'exposez pas publiquement sans authentification et TLS. Pour un accès d'administration temporaire, depuis une machine ayant accès au cluster :

```bash
kubectl port-forward --namespace longhorn-system \
  service/longhorn-frontend 8080:80
```

Ouvrir <http://localhost:8080> sur cette même machine, puis arrêter le port-forward après usage. Pour une exposition permanente avec Traefik, suivre le guide officiel Longhorn sur [Ingress Traefik avec authentification](https://longhorn.io/docs/1.13.0/deploy/accessing-the-ui/longhorn-ingress-traefik/).

## Références officielles

- [Installation et prérequis Longhorn 1.13](https://longhorn.io/docs/1.13.0/deploy/install/)
- [Installation avec Helm](https://longhorn.io/docs/1.13.0/deploy/install/install-with-helm/)
- [Création de volumes et PVC](https://longhorn.io/docs/1.13.0/nodes-and-volumes/volumes/create-volumes/)
- [Paramètres du StorageClass](https://longhorn.io/docs/1.13.0/references/storage-class-parameters/)
- [Valeurs par défaut du chart Helm](https://github.com/longhorn/longhorn/blob/v1.13.0/chart/values.yaml)