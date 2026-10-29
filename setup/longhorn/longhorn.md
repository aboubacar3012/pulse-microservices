# Installer et configurer Longhorn

Ce guide installe Longhorn sur un cluster kubeadm avec Helm, configure le StorageClass `longhorn` par défaut et teste un volume.

Les commandes sont à lancer depuis la racine du dépôt, avec `kubectl` configuré pour le cluster cible. La configuration Helm se trouve dans [`values.yaml`](./values.yaml).

## 1. Vérifier les prérequis

La configuration utilise Longhorn **1.13.0**, dont le chart exige Kubernetes **1.34 ou supérieur** :

```bash
kubectl version
```

Sur chaque nœud Linux destiné au stockage, installer iSCSI :

```bash
sudo apt-get update
sudo apt-get install -y open-iscsi
sudo systemctl enable --now iscsid
sudo modprobe iscsi_tcp
```

Pour utiliser des volumes RWX ou des sauvegardes NFS, installer aussi `nfs-common`.

Vérifier que iSCSI est actif :

```bash
systemctl is-active iscsid
iscsiadm --version
lsmod | grep iscsi_tcp
```

Ne pas utiliser `open-iscsi` **2.1.12** : Longhorn signale une incompatibilité critique.

## 2. Préparer les disques

Longhorn utilise `/var/lib/longhorn` et ne crée des disques que sur les nœuds portant le label configuré.

Sur chaque nœud de stockage :

1. Monter le disque persistant à `/var/lib/longhorn`.
2. Vérifier son montage et l'espace disponible :

```bash
findmnt -T /var/lib/longhorn
df -h /var/lib/longhorn
```

Puis, depuis une machine ayant accès au cluster, activer le nœud :

```bash
kubectl label node <NOM_DU_NOEUD> node.longhorn.io/create-default-disk=true
```

Répéter pour chaque nœud éligible. Ne pas appliquer ce label avant d'avoir monté le disque voulu.

## 3. Installer Longhorn

La configuration dans [`values.yaml`](./values.yaml) :

- crée `longhorn` comme StorageClass par défaut et utilise `/var/lib/longhorn` ;
- configure trois réplicas par volume; il faut trois nœuds de stockage, et les réplicas utilisent environ trois fois la capacité logique ;
- réserve 25 % d'espace disque et limite la surallocation à 100 % ;
- limite les ressources CPU/mémoire de Longhorn Manager et Global Manager.

Pour un cluster à un seul nœud, régler `persistence.defaultClassReplicaCount` à `1` dans le fichier avant l'installation. Cela désactive la redondance des volumes.

Vérifier les StorageClass existants avant installation :

```bash
kubectl get storageclass
```

La configuration marque `longhorn` comme StorageClass par défaut. Éviter d'avoir plusieurs classes par défaut.

Installer la version configurée :

```bash
helm repo add longhorn https://charts.longhorn.io
helm repo update
helm upgrade --install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace \
  --version 1.13.0 \
  --values setup/longhorn/values.yaml
```

Vérifier le déploiement :

```bash
kubectl rollout status deployment/longhorn-driver-deployer \
  --namespace longhorn-system \
  --timeout=300s
kubectl get pods --namespace longhorn-system
kubectl get storageclass
kubectl get nodes.longhorn.io --namespace longhorn-system
```

Le StorageClass `longhorn` doit être marqué `(default)` et les nœuds/disques doivent être sains.

## 4. Tester un volume

Créer un PVC et un pod de test :

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

Vérifier le PVC et le pod :

```bash
kubectl get pvc,pod --namespace default
kubectl logs longhorn-test --namespace default
```

Les journaux doivent afficher `longhorn-ok`. Après le test, supprimer les ressources de test (cela supprime le volume associé) :

```bash
kubectl delete pod longhorn-test --namespace default
kubectl delete pvc longhorn-test --namespace default
```

## 5. Ouvrir l'interface d'administration

L'interface Longhorn n'a pas d'authentification intégrée. Pour un accès temporaire, lancer :

```bash
kubectl port-forward --namespace longhorn-system \
  service/longhorn-frontend 8080:80
```

Ouvrir <http://localhost:8080>, puis arrêter le port-forward après usage. Ne pas exposer l'interface publiquement sans HTTPS et authentification.

## En cas de problème

```bash
kubectl get pods,pvc --all-namespaces
kubectl get events --namespace longhorn-system --sort-by=.lastTimestamp
kubectl get volumes.longhorn.io --namespace longhorn-system
```

Vérifier les événements du PVC bloqué, l'état des nœuds/disques Longhorn, l'espace libre et le service `iscsid`.
