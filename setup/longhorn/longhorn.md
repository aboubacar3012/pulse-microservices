# Installer Longhorn

Cette procédure installe Longhorn **1.13.0**, configure `longhorn` comme StorageClass par défaut et vérifie le stockage.

Exécuter les commandes depuis la racine du dépôt avec `kubectl` configuré pour le cluster cible. Les valeurs sont dans [`values.yaml`](./values.yaml).

## 1. Préparer les nœuds

Longhorn 1.13.0 nécessite Kubernetes 1.34 ou supérieur :

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

Vérifier :

```bash
systemctl is-active iscsid
iscsiadm --version
```

Ne pas utiliser `open-iscsi` 2.1.12. Pour les volumes RWX ou sauvegardes NFS, installer aussi `nfs-common`.

Monter un disque persistant à `/var/lib/longhorn` sur chaque nœud de stockage :

```bash
findmnt -T /var/lib/longhorn
df -h /var/lib/longhorn
```

Après vérification du montage, labelliser chaque nœud depuis la machine d'administration :

```bash
kubectl label node <NOM_DU_NOEUD> node.longhorn.io/create-default-disk=true
```

## 2. Installer Longhorn

Le fichier [`values.yaml`](./values.yaml) configure les limites CPU/mémoire et les seuils d'espace disque. Il crée trois réplicas par volume : prévoir trois nœuds de stockage; pour un cluster à un seul nœud, régler `persistence.defaultClassReplicaCount: 1` dans ce fichier avant l'installation.

Vérifier les StorageClass existants :

```bash
kubectl get storageclass
```

Puis installer :

```bash
helm repo add longhorn https://charts.longhorn.io
helm repo update
helm upgrade --install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace \
  --version 1.13.0 \
  --values setup/longhorn/values.yaml
```

Attendre la disponibilité et vérifier le StorageClass :

```bash
kubectl rollout status deployment/longhorn-driver-deployer \
  --namespace longhorn-system \
  --timeout=300s
kubectl get pods -n longhorn-system
kubectl get storageclass
kubectl get nodes.longhorn.io -n longhorn-system
```

`longhorn` doit apparaître comme classe par défaut et les nœuds/disques doivent être prêts.

## 3. Tester un volume

Créer un PVC et un pod de test :

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: longhorn-test
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: longhorn-test
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

Vérifier que le PVC est `Bound` et que les logs affichent `longhorn-ok` :

```bash
kubectl get pvc,pod
kubectl logs longhorn-test
```

Le PVC doit être `Bound` et les logs doivent afficher `longhorn-ok`.

Après le test, supprimer les ressources (le volume de test sera supprimé) :

```bash
kubectl delete pod longhorn-test
kubectl delete pvc longhorn-test
```

## 4. Ouvrir l'interface d'administration

L'interface n'a pas d'authentification intégrée. Pour un accès temporaire :

```bash
kubectl port-forward -n longhorn-system service/longhorn-frontend 8080:80
```

Ouvrir <http://localhost:8080>. Ne pas exposer l'interface publiquement sans HTTPS et authentification.

En cas de problème :

```bash
kubectl get pods,pvc -A
kubectl get events -n longhorn-system --sort-by=.lastTimestamp
```
