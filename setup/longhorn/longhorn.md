# Longhorn — architecture, stockage et limites de ressources

Ce document explique la configuration Longhorn installée par [`storageclass.md`](./storageclass.md), avec les valeurs Helm de [`longhorn/values.yaml`](./longhorn/values.yaml).

## Ce que cette installation apporte

Longhorn fournit du stockage bloc persistant à Kubernetes. Un PVC utilisant le StorageClass `longhorn` déclenche le provisionnement d'un volume Longhorn; le CSI driver permet ensuite à Kubernetes d'attacher et de monter ce volume dans un pod.

La configuration retenue :

- installe Longhorn **1.13.0** avec Helm dans `longhorn-system` ;
- utilise le moteur de données **V1**, activé par défaut ;
- utilise le chemin local `/var/lib/longhorn` pour les réplicas ;
- crée des disques uniquement sur les nœuds explicitement labellisés `node.longhorn.io/create-default-disk=true` ;
- crée le StorageClass `longhorn` et le définit comme classe par défaut ;
- configure **3 réplicas** pour les nouveaux volumes ;
- réserve au moins **25 %** de l'espace disque disponible et ne permet pas la surallocation de capacité au-delà de **100 %** ;
- définit des requests et limites de ressources pour Longhorn Manager et Longhorn Global Manager.

Longhorn est un système de stockage, **pas un système de sauvegarde**. Des réplicas peuvent protéger contre la perte d'un disque ou d'un nœud selon le placement, mais pas contre une suppression accidentelle, une corruption propagée ou la perte du cluster entier. Configurer un backup target externe et tester la restauration pour protéger les données.

## Comment les données sont placées

Lorsqu'un pod demande un PVC `ReadWriteOnce`, le provisionneur Longhorn crée un volume et répartit ses réplicas sur les nœuds et disques Longhorn éligibles. Avec `numberOfReplicas: "3"`, Longhorn vise trois copies indépendantes. Les trois copies consomment approximativement trois fois la capacité logique du volume, hors métadonnées et snapshots.

Les trois réplicas doivent pouvoir être placés sur des nœuds de stockage distincts. Trois réplicas ne rendent pas un cluster à un ou deux nœuds hautement disponible. Pour un lab à un nœud, régler `persistence.defaultClassReplicaCount` à `1`; cela supprime la redondance. Pour deux nœuds, utiliser `2`, en comprenant que les deux copies dépendent de ces deux nœuds.

Les données sont stockées sur le système de fichiers du disque Longhorn. Le chemin `/var/lib/longhorn` doit donc être placé sur un disque persistant et suffisamment grand, et non laissé par inadvertance sur une petite partition système. Le guide d'installation demande de monter le disque avant de labelliser le nœud afin que Longhorn ne crée pas son disque sur le mauvais volume.

### Capacité et planification

Le paramètre `storageOverProvisioningPercentage: 100` empêche Longhorn de planifier plus de capacité logique que la capacité disponible selon ses règles de planification. Avec `storageMinimalAvailablePercentage: 25`, Longhorn garde une marge minimale pour le disque.

Ces paramètres ne constituent pas une réservation de capacité pour chaque application et ne remplacent pas la supervision. Il faut également tenir compte du nombre de réplicas, des snapshots, de la croissance des données et des opérations de reconstruction. Un volume logique de 10 GiB avec trois réplicas nécessite environ 30 GiB d'espace brut avant cette marge.

## Limites CPU et mémoire configurées

Le fichier Helm fixe les budgets suivants :

| Composant               | Request CPU / mémoire | Limite CPU / mémoire | Portée                                                          |
| ----------------------- | --------------------: | -------------------: | --------------------------------------------------------------- |
| Longhorn Manager        |      `100m` / `128Mi` |     `1` vCPU / `1Gi` | Un pod Manager par nœud où Longhorn s'exécute                   |
| Longhorn Global Manager |      `100m` / `256Mi` |     `1` vCPU / `1Gi` | Chaque pod Global Manager; le chart en déploie trois par défaut |

Les **requests** servent au scheduler Kubernetes pour réserver des ressources et placer les pods. Les **limits** plafonnent leur consommation : une limite CPU peut entraîner du throttling sous charge; un dépassement de mémoire peut provoquer un OOMKill. Ces valeurs sont un point de départ modéré, pas des seuils universels ni une recommandation du fournisseur Longhorn. Le Global Manager garde en mémoire un cache qui évolue avec le nombre de pods dans le cluster; augmentez sa limite si vous observez une pression mémoire ou des redémarrages.

Ces réglages ne plafonnent **pas** toute la consommation Longhorn :

- le moteur V1 lance des composants de données et d'instance pour attacher et servir les volumes ;
- les réplicas et reconstructions consomment CPU, mémoire et surtout E/S disque/réseau ;
- certains composants du chart n'exposent pas de réglage `resources` dans les valeurs du chart 1.13.0.

Ne pas appliquer une `ResourceQuota` générique à `longhorn-system` ni ajouter des limites arbitraires à tous les composants : cela peut empêcher les pods système ou les composants CSI de démarrer et rendre les volumes indisponibles. Observer d'abord les métriques et événements, puis dimensionner les limites de manière progressive.

Les valeurs de ressources ne remplacent pas les prérequis matériels. Pour sa configuration de production recommandée avec V1, Longhorn indique trois nœuds, quatre vCPU et 4 GiB de mémoire par nœud, avec SSD/NVMe recommandé. Ces besoins incluent les workloads Kubernetes et la charge de stockage; les limites ci-dessus ne peuvent pas rendre adéquat un nœud trop petit.

## Comment Kubernetes utilise le StorageClass par défaut

Le StorageClass `longhorn` est marqué par défaut. Un PVC sans `storageClassName` peut alors être provisionné par Longhorn, ce qui facilite la création d'applications, mais peut aussi placer des données sur Longhorn sans décision explicite de l'équipe.

Avant l'installation, vérifier les StorageClass existants. Éviter plusieurs StorageClass marqués par défaut. Pour les workloads importants, définir explicitement `storageClassName: longhorn` dans les PVC permet de rendre la dépendance visible et évite les surprises si le StorageClass par défaut change.

La politique de récupération par défaut est `Delete` : supprimer un PVC peut supprimer le volume associé. Pour les données à conserver, vérifier le cycle de vie du workload, la politique du StorageClass et les sauvegardes avant de supprimer des PVC.

## Accès à l'interface et sécurité

L'interface Longhorn permet de gérer les volumes et les paramètres de stockage; elle n'active pas l'authentification par défaut lors d'une installation Helm. Le guide d'installation recommande un `kubectl port-forward` temporaire pour l'administration locale. Pour une exposition durable, utiliser HTTPS et authentification via une configuration Traefik protégée, comme décrit dans la documentation officielle Longhorn, et restreindre l'accès au personnel d'exploitation.

Longhorn nécessite des composants privilégiés avec accès aux ressources système des hôtes pour gérer les volumes. Installer Longhorn uniquement sur un cluster et des nœuds de confiance, maintenir Kubernetes et Longhorn à jour, et ne pas exposer l'interface d'administration publiquement sans contrôle d'accès.

## Vérifications d'exploitation

Après installation ou lors d'un incident, contrôler :

```bash
kubectl get pods -n longhorn-system
kubectl get storageclass
kubectl get nodes.longhorn.io -n longhorn-system
kubectl get volumes.longhorn.io -n longhorn-system
kubectl get events -n longhorn-system --sort-by=.lastTimestamp
```

Dans l'interface Longhorn, vérifier l'état des nœuds, des disques, des volumes et des réplicas. Surveiller en particulier :

- les PVC bloqués en `Pending` ;
- les volumes `Degraded` ou `Faulted` ;
- les nœuds ou disques `NotReady` / `Unschedulable` ;
- l'espace libre et la croissance des snapshots ;
- les OOMKills, redémarrages ou événements de throttling des pods Longhorn ;
- les erreurs iSCSI et les échecs d'attachement.

## Références

- [Guide d'installation](./storageclass.md)
- [Valeurs Helm appliquées](./longhorn/values.yaml)
- [Bonnes pratiques et matériel recommandé](https://longhorn.io/docs/1.13.0/best-practices/)
- [Prérequis de la version 1.13.0](https://longhorn.io/docs/1.13.0/deploy/install/)
- [Paramètres du StorageClass](https://longhorn.io/docs/1.13.0/references/storage-class-parameters/)
