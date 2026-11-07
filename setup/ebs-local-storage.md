# Stockage local Kubernetes sur AWS Lightsail

Ce guide ajoute un disque persistant à une instance Lightsail et l'utilise comme
espace de stockage local pour Kubernetes avec le provisionneur `local-path`.

> **Important : Lightsail n'utilise pas les volumes EBS EC2.** Un volume EBS
> classique ne peut pas être attaché directement à une instance Lightsail.
> Lightsail propose son propre type de **disque de stockage (block storage)**,
> que l'on peut attacher à une instance. Pour utiliser réellement EBS et le
> pilote CSI EBS de Kubernetes, les nœuds doivent être des instances EC2
> compatibles, pas des instances Lightsail.

## Ce que cette solution apporte (et ses limites)

- Le disque Lightsail fournit un espace de stockage qui reste attaché à la même
  instance après un redémarrage.
- `local-path` crée les volumes Kubernetes sur ce disque, dans
  `/opt/local-path-provisioner` (chemin utilisé par le guide
  [local-path](./local-path-storage-class.md)).
- Un volume ainsi créé reste **local à un seul nœud**. Il n'est ni répliqué ni
  automatiquement disponible sur un autre nœud si l'instance tombe.
- Chaque nœud pouvant héberger ces pods doit avoir son propre disque Lightsail
  attaché et monté au même chemin. Sinon, limiter les pods concernés au nœud
  équipé du disque.
- Prévoir des sauvegardes. Une sauvegarde de disque ou un snapshot ne remplace
  pas une stratégie de restauration testée.

## 1. Créer et attacher le disque Lightsail

Dans la console AWS :

1. Ouvrir **Lightsail → Storage** et créer un disque de stockage dans la même
   région et zone de disponibilité que l'instance Kubernetes cible.
2. Choisir une taille adaptée et un nom explicite, par exemple
   `k8s-w1-data`.
3. Attacher le disque à l'instance cible et attendre que son état indique qu'il
   est attaché.

Un disque Lightsail est attaché à une instance donnée : créer un disque
distinct pour chaque nœud qui doit en avoir un. Ne pas essayer d'attacher le
même disque à plusieurs instances.

## 2. Repérer le disque sur l'instance

Se connecter en SSH à l'instance et identifier le nouveau périphérique :

```bash
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS,UUID
```

Comparer la sortie avant/après l'attachement si nécessaire. Dans les commandes
ci-dessous, remplacer `/dev/DEVICE` par le périphérique effectivement repéré
(par exemple `/dev/xvdf` si c'est bien celui qui apparaît). **Ne pas deviner le
nom du périphérique** et ne jamais formater le disque système ou un disque qui
contient déjà des données.

Si le disque est neuf et vide, créer un système de fichiers ext4 :

```bash
sudo mkfs.ext4 /dev/DEVICE
```

`mkfs` efface les données déjà présentes sur le périphérique. Si le disque
contient des données à conserver, ne pas exécuter cette commande : vérifier son
contenu et définir une procédure de sauvegarde/migration avant de continuer.

Récupérer l'UUID du système de fichiers :

```bash
sudo blkid /dev/DEVICE
```

## 3. Monter le disque pour `local-path`

Le guide `local-path` utilise `/opt/local-path-provisioner` sur le nœud. Monter
le disque à ce chemin afin que les nouveaux PVC soient stockés dessus.

Créer le point de montage :

```bash
sudo mkdir -p /opt/local-path-provisioner
```

Ajouter une entrée dans `/etc/fstab`, en remplaçant `UUID_DU_DISQUE` par
l'UUID renvoyé par `blkid` :

```fstab
UUID=UUID_DU_DISQUE /opt/local-path-provisioner ext4 defaults 0 2
```

Par exemple, éditer le fichier avec :

```bash
sudo nano /etc/fstab
```

Monter et vérifier le disque :

```bash
sudo mount -a
findmnt /opt/local-path-provisioner
df -h /opt/local-path-provisioner
```

Vérifier que `findmnt` indique bien le disque Lightsail, puis redémarrer
l'instance pendant une fenêtre de maintenance et refaire ces vérifications.
Cela confirme que le montage persiste après redémarrage.

### Si `local-path` est déjà utilisé

Ne pas monter le disque par-dessus un répertoire qui contient des volumes
existants : le montage masquerait ces fichiers. Avant toute migration :

1. Recenser les PVC/PV et sauvegarder les données applicatives.
2. Arrêter proprement les applications qui écrivent dans les volumes concernés.
3. Copier les données de `/opt/local-path-provisioner` vers le nouveau disque,
   puis monter celui-ci au chemin définitif.
4. Vérifier les données et le montage avant de relancer les applications.

Ne pas supprimer les anciens fichiers ni les PVC tant que la restauration n'a
pas été vérifiée. Un PVC existant ne change pas de nœud ou de `StorageClass`
simplement parce qu'un disque a été ajouté.

## 4. Installer ou vérifier `local-path`

Répéter les étapes 1 à 3 pour chaque nœud susceptible d'héberger les pods qui
utiliseront ces PVC, puis suivre le [guide d'installation de local-path](./local-path-storage-class.md).
Si `local-path` est déjà installé, vérifier le provisionneur et la StorageClass :

```bash
kubectl get nodes -o wide
kubectl get pods -n local-path-storage
kubectl get storageclass local-path
```

Un PVC `local-path` sera lié au nœud sur lequel son volume est créé. Si un seul
nœud possède le disque, configurer les workloads concernés pour qu'ils
s'exécutent sur ce nœud, et vérifier cette contrainte avant de déployer.

## 5. Tester avec un PVC

Créer un PVC de test, en indiquant explicitement la StorageClass :

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: lightsail-storage-test
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: lightsail-storage-test
spec:
  containers:
    - name: test
      image: busybox:1.36
      command: ["sh", "-c", "echo lightsail-storage-ok > /data/check.txt && cat /data/check.txt && sleep 3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: lightsail-storage-test
```

Enregistrer le manifeste sous `lightsail-storage-test.yaml`, puis l'appliquer et
vérifier le pod, le PVC et le nœud d'affectation :

```bash
kubectl apply -f lightsail-storage-test.yaml
kubectl wait --for=condition=Ready pod/lightsail-storage-test --timeout=120s
kubectl get pvc,pod -o wide
kubectl logs lightsail-storage-test
kubectl describe pv
```

Les logs doivent afficher `lightsail-storage-ok` et le PVC doit être `Bound`.
Vérifier que le pod est planifié sur un nœud équipé d'un disque. Après le test,
supprimer les ressources uniquement si aucune donnée à conserver n'y a été
écrite :

```bash
kubectl delete pod lightsail-storage-test
kubectl delete pvc lightsail-storage-test
```

## Dépannage

Sur l'instance Lightsail :

```bash
lsblk -f
findmnt /opt/local-path-provisioner
df -h /opt/local-path-provisioner
```

Dans Kubernetes :

```bash
kubectl describe pvc <nom-du-pvc>
kubectl describe pod <nom-du-pod>
kubectl get events -A --sort-by=.lastTimestamp
```

Si le disque n'est pas monté, ne pas laisser les workloads écrire dans le
répertoire sous-jacent du système : vérifier le périphérique et l'entrée
`/etc/fstab` avant de redémarrer les applications.