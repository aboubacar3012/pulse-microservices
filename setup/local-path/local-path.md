# Installer local-path

Ce guide installe le provisionneur Rancher `local-path` **v0.0.37** et vérifie qu'il peut créer un volume persistant. Exécuter les commandes depuis une machine d'administration avec `kubectl` configuré pour le cluster cible.

## À savoir avant de commencer

`local-path` stocke les données directement sur le disque local du nœud Kubernetes où le volume est créé. Il ne réplique pas les données entre les nœuds et n'offre pas de bascule automatique vers un autre nœud. Un pod utilisant ce volume devra rester planifié sur le nœud qui contient les données. Prévoir des sauvegardes et assez d'espace disque sur les nœuds.

Par défaut, le provisionneur utilise `/opt/local-path-provisioner` sur le nœud. Il n'est donc pas nécessaire de préparer ou monter un disque Longhorn à `/var/lib/longhorn`.

Cette installation ne migre pas et ne désinstalle pas Longhorn. Ne pas supprimer Longhorn tant que des volumes ou PVC existants en dépendent. Un PVC existant ne peut pas changer directement de `storageClassName` : sauvegarder les données, créer un nouveau PVC `local-path`, puis restaurer les données avant de retirer l'ancien stockage.

## 1. Installer le provisionneur

Appliquer le manifeste officiel versionné :

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.37/deploy/local-path-storage.yaml
```

Attendre que le provisionneur soit prêt et vérifier la StorageClass :

```bash
kubectl rollout status deployment/local-path-provisioner \
  --namespace local-path-storage \
  --timeout=180s
kubectl get pods --namespace local-path-storage
kubectl get storageclass local-path
```

Le manifeste crée la StorageClass `local-path`, qui n'est pas définie par défaut. Dans les manifestes et valeurs Helm, indiquer explicitement `storageClassName: local-path` ou `storageClass: local-path`.

## 2. Tester un volume

Créer un PVC et un pod de test :

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: local-path-test
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: local-path
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: local-path-test
spec:
  containers:
    - name: test
      image: busybox:1.36
      command: ["sh", "-c", "echo local-path-ok > /data/check.txt && cat /data/check.txt && sleep 3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: local-path-test
EOF
```

Vérifier que le pod est prêt, que le PVC est `Bound` et que les logs affichent `local-path-ok` :

```bash
kubectl wait --for=condition=Ready pod/local-path-test --timeout=120s
kubectl get pvc,pod
kubectl logs local-path-test
```

Après vérification, supprimer les ressources. La suppression du PVC entraîne la suppression des données de ce volume :

```bash
kubectl delete pod local-path-test
kubectl delete pvc local-path-test
```

En cas de problème :

```bash
kubectl get pods,pvc -A
kubectl get events --namespace local-path-storage --sort-by=.lastTimestamp
```
