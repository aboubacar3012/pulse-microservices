# Installer Argo Rollouts et accéder au dashboard

Argo Rollouts ajoute à Kubernetes des déploiements progressifs, notamment Canary et Blue-Green. Ce guide installe le contrôleur et le plugin `kubectl`, décrit l'accès recommandé au dashboard avec un tunnel SSH, propose aussi son déploiement optionnel derrière un `NodePort`, puis vérifie le fonctionnement avec un Rollout Canary de démonstration.

Les commandes supposent que `kubectl` est configuré pour le cluster cible et que l'utilisateur peut créer des ressources cluster-scoped (CRD, rôles et bindings). L'exemple utilise Argo Rollouts **v1.10.1** ; vérifier la compatibilité avec la version Kubernetes du cluster avant une installation différente.

> **Sécurité :** le dashboard n'a pas d'authentification intégrée. L'accès par CLI utilise les identifiants et les permissions Kubernetes de l'utilisateur qui lance la commande. Le tunnel SSH garde le port du dashboard sur la boucle locale : ne pas le lier à `0.0.0.0` et ne pas ouvrir le port `3100` dans le pare-feu. Le `NodePort` est une option moins sûre : ne l'activer que si nécessaire et limiter son accès à une IP d'administration de confiance.

## 1. Installer le contrôleur

Créer le namespace et appliquer le manifeste officiel de la version choisie :

```bash
kubectl create namespace argo-rollouts \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply --namespace argo-rollouts \
  -f https://github.com/argoproj/argo-rollouts/releases/download/v1.10.1/install.yaml
```

Le manifeste installe les CRD et le contrôleur. Attendre son démarrage et vérifier les ressources :

```bash
kubectl rollout status deployment/argo-rollouts \
  --namespace argo-rollouts \
  --timeout=300s
kubectl get pods --namespace argo-rollouts
kubectl get crd | grep argoproj.io
```

Le pod `argo-rollouts` doit être `Running`.

Vérifier que la CRD des Rollouts est disponible :

```bash
kubectl get crd rollouts.argoproj.io
```

Si l'application du manifeste affiche `metadata.annotations: Too long` pour `rollouts.argoproj.io` ou `analysisruns.argoproj.io`, ces CRD volumineuses dépassent la limite de l'annotation utilisée par `kubectl apply` en mode client. Appliquer uniquement les CRD manquantes avec Server-Side Apply :

```bash
kubectl apply --server-side \
  -f https://raw.githubusercontent.com/argoproj/argo-rollouts/v1.10.1/manifests/crds/rollout-crd.yaml \
  -f https://raw.githubusercontent.com/argoproj/argo-rollouts/v1.10.1/manifests/crds/analysis-run-crd.yaml
```

Attendre que Kubernetes les ait établies, puis vérifier :

```bash
kubectl wait --for condition=Established \
  crd/rollouts.argoproj.io \
  crd/analysisruns.argoproj.io \
  --timeout=120s
kubectl get crd rollouts.argoproj.io analysisruns.argoproj.io
```

## 2. Installer le plugin CLI

Le plugin CLI permet d'inspecter et de gérer les Rollouts avec `kubectl`. Pour Ubuntu Linux amd64 :

```bash
ARGO_ROLLOUTS_VERSION='1.10.1'
curl -fLO "https://github.com/argoproj/argo-rollouts/releases/download/v${ARGO_ROLLOUTS_VERSION}/kubectl-argo-rollouts-linux-amd64"
chmod +x kubectl-argo-rollouts-linux-amd64
sudo install -m 755 kubectl-argo-rollouts-linux-amd64 \
  /usr/local/bin/kubectl-argo-rollouts
rm kubectl-argo-rollouts-linux-amd64
kubectl argo rollouts version
```

Pour un autre système ou une autre architecture, télécharger le binaire correspondant depuis les [versions officielles](https://github.com/argoproj/argo-rollouts/releases).

## 3. Accéder au dashboard avec un tunnel SSH

Le dashboard est lancé par le plugin CLI sur la machine où la commande est exécutée ; il n'est pas nécessaire de déployer un dashboard supplémentaire dans Kubernetes. Pour un accès sécurisé depuis un ordinateur, lancer le dashboard sur le serveur qui possède `kubectl` et le kubeconfig donnant accès au cluster, puis établir un tunnel SSH depuis l'ordinateur.

### Sur le serveur

Dans une première session SSH vers le serveur, lancer le dashboard. Le serveur écoute par défaut sur `127.0.0.1:3100`, pas sur son interface publique. Remplacer `default` par le namespace dans lequel se trouvent les Rollouts à afficher :

```bash
kubectl argo rollouts dashboard \
  --address 127.0.0.1 \
  --port 3100 \
  --namespace default
```

Garder cette commande active. Le terminal doit annoncer que le dashboard est disponible sur le port `3100`.

### Depuis l'ordinateur d'administration

Dans un second terminal de l'ordinateur, protéger le fichier de clé privée puis ouvrir le tunnel SSH. Placer `gitops-practices.pem` dans `~/.ssh/` et remplacer l'adresse publique par celle du serveur :

```bash
chmod 400 ~/.ssh/gitops-practices.pem
ssh -i ~/.ssh/gitops-practices.pem \
  -N -L 3100:127.0.0.1:3100 \
  ubuntu@100.29.247.143
```

Garder cette connexion SSH active et ouvrir <http://localhost:3100/rollouts> dans le navigateur. Lorsque la consultation est terminée, fermer le tunnel avec `Ctrl+C`, puis arrêter le dashboard sur le serveur avec `Ctrl+C`.

Le port `3100` n'a pas besoin d'être ouvert dans le pare-feu du serveur ou du fournisseur cloud. Il suffit que SSH soit accessible depuis l'ordinateur d'administration. Si le port local `3100` est déjà utilisé, choisir par exemple `13100` côté ordinateur :

```bash
ssh -i ~/.ssh/gitops-practices.pem \
  -N -L 13100:127.0.0.1:3100 \
  ubuntu@IP_PUBLIQUE_DU_SERVEUR
```

Dans ce cas, ouvrir <http://localhost:13100/rollouts>.

## Option — Déployer le dashboard avec un NodePort

Utiliser cette option à la place du tunnel SSH si l'accès direct par navigateur est nécessaire. Le NodePort expose le dashboard en HTTP et sans authentification. Son ServiceAccount dispose de permissions Kubernetes étendues sur les Rollouts et les Deployments : toute personne qui atteint le dashboard peut effectuer des opérations avec ces permissions. Ne pas autoriser l'accès depuis toutes les adresses Internet.

Déployer le dashboard officiel de la **même version** que le contrôleur :

```bash
kubectl apply --namespace argo-rollouts \
  -f https://raw.githubusercontent.com/argoproj/argo-rollouts/v1.10.1/manifests/dashboard-install.yaml
kubectl set image deployment/argo-rollouts-dashboard \
  argo-rollouts-dashboard=quay.io/argoproj/kubectl-argo-rollouts:v1.10.1 \
  --namespace argo-rollouts
kubectl rollout status deployment/argo-rollouts-dashboard \
  --namespace argo-rollouts \
  --timeout=300s
```

Le manifeste officiel crée le ServiceAccount, les permissions RBAC, le Deployment et le Service dashboard. Remplacer le Service par un Service `NodePort` sur le port TCP `31000` :

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: argo-rollouts-dashboard
  namespace: argo-rollouts
spec:
  type: NodePort
  selector:
    app.kubernetes.io/name: argo-rollouts-dashboard
  ports:
    - name: http
      protocol: TCP
      port: 3100
      targetPort: 3100
      nodePort: 31000
EOF
```

Vérifier que le pod est prêt et que le Service affiche `3100:31000/TCP` :

```bash
kubectl get pods,service --namespace argo-rollouts -o wide
kubectl get endpoints argo-rollouts-dashboard --namespace argo-rollouts
```

Dans **Lightsail → Instance → Networking → Firewall**, ajouter une règle **Custom / TCP / 31000**. Restreindre la source à l'adresse IP publique d'administration (`<IP_ADMIN>/32`) ; ne pas choisir `Anywhere IPv4`. Ne pas ouvrir le port `3100`, qui est le port interne du Service.

Depuis le poste autorisé, ouvrir `http://<IP_PUBLIQUE_DU_SERVEUR>:31000/rollouts`. Le NodePort est accessible sur l'adresse de chaque nœud, sous réserve des règles de pare-feu et du routage réseau.

Pour désactiver l'accès NodePort, rétablir le Service en `ClusterIP` et supprimer la règle TCP 31000 du pare-feu Lightsail :

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: argo-rollouts-dashboard
  namespace: argo-rollouts
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: argo-rollouts-dashboard
  ports:
    - name: http
      protocol: TCP
      port: 3100
      targetPort: 3100
EOF
```

Le dashboard déployé et ses permissions restent présents dans le cluster. Le tunnel SSH décrit plus haut lance une instance locale du dashboard avec le plugin CLI et n'a pas besoin de ces ressources.

## 4. Vérifier avec un Rollout Canary de démonstration

Créer un Rollout et un Service dans le namespace `default` :

```bash
kubectl apply -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: rollout-demo
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: rollout-demo
  template:
    metadata:
      labels:
        app: rollout-demo
    spec:
      containers:
        - name: rollout-demo
          image: argoproj/rollouts-demo:blue
          ports:
            - name: http
              containerPort: 8080
  strategy:
    canary:
      steps:
        - setWeight: 33
        - pause: {}
        - setWeight: 66
        - pause:
            duration: 30s
---
apiVersion: v1
kind: Service
metadata:
  name: rollout-demo
  namespace: default
spec:
  selector:
    app: rollout-demo
  ports:
    - name: http
      port: 80
      targetPort: http
EOF
```

Le premier déploiement d'un Rollout crée sa version initiale directement ; les étapes Canary sont exécutées lors d'une mise à jour. Sans intégration de routage de trafic (Ingress ou service mesh compatible), `setWeight` ajuste au mieux le ratio des réplicas et ne garantit pas un pourcentage exact de requêtes.

Suivre le déploiement :

```bash
kubectl argo rollouts get rollout rollout-demo --namespace default --watch
```

Mettre à jour l'image pour déclencher le Canary :

```bash
kubectl argo rollouts set image rollout-demo \
  rollout-demo=argoproj/rollouts-demo:yellow \
  --namespace default
```

Le Rollout s'arrête à l'étape `pause: {}`. Le voir dans le dashboard, puis le faire avancer :

```bash
kubectl argo rollouts promote rollout-demo --namespace default
```

Le dernier `pause` reprend automatiquement après 30 secondes, puis le Rollout termine la mise à jour. Vérifier son état :

```bash
kubectl argo rollouts get rollout rollout-demo --namespace default
kubectl get pods --namespace default -l app=rollout-demo
```

Pour tester l'annulation d'une mise à jour, déclencher un nouvel update, attendre la pause, puis annuler :

```bash
kubectl argo rollouts set image rollout-demo \
  rollout-demo=argoproj/rollouts-demo:red \
  --namespace default
```

Attendre que le Rollout atteigne la pause Canary, puis l'annuler :

```bash
kubectl argo rollouts get rollout rollout-demo --namespace default --watch
kubectl argo rollouts abort rollout-demo --namespace default
```

Un Rollout annulé peut rester `Degraded` tant que l'image désirée est toujours celle qui a échoué. Remettre explicitement l'image stable pour revenir à un état sain :

```bash
kubectl argo rollouts set image rollout-demo \
  rollout-demo=argoproj/rollouts-demo:yellow \
  --namespace default
kubectl argo rollouts get rollout rollout-demo --namespace default
```

Après le test, supprimer les ressources :

```bash
kubectl delete rollout rollout-demo --namespace default
kubectl delete service rollout-demo --namespace default
```

## 5. Commandes utiles

```bash
# Lister les Rollouts dans tous les namespaces
kubectl argo rollouts list rollouts --all-namespaces

# Afficher un Rollout et suivre son évolution
kubectl argo rollouts get rollout <NOM> --namespace <NAMESPACE> --watch

# Reprendre une pause manuelle
kubectl argo rollouts promote <NOM> --namespace <NAMESPACE>

# Annuler la mise à jour en cours
kubectl argo rollouts abort <NOM> --namespace <NAMESPACE>

# Afficher l'historique des révisions
kubectl argo rollouts history rollout <NOM> --namespace <NAMESPACE>
```

## Dépannage

Vérifier l'état du contrôleur, des CRD et les événements du namespace :

```bash
kubectl get pods --namespace argo-rollouts -o wide
kubectl get crd rollouts.argoproj.io
kubectl get events --namespace argo-rollouts --sort-by=.lastTimestamp
kubectl logs deployment/argo-rollouts \
  --namespace argo-rollouts \
  --since=10m
```

- **Pod en `ImagePullBackOff`** : vérifier l'accès à Quay et l'image versionnée `v1.10.1`.
- **Le navigateur n'ouvre pas le dashboard** : vérifier que la commande `kubectl argo rollouts dashboard` est toujours active sur le serveur et que le tunnel SSH est toujours ouvert ; confirmer le port local utilisé dans l'URL.
- **Le tunnel SSH signale que le port local est occupé** : utiliser un autre port local, par exemple `13100:127.0.0.1:3100`, puis ouvrir <http://localhost:13100/rollouts>.
- **Erreurs d'autorisation dans le dashboard** : la CLI utilise le contexte et les permissions de l'utilisateur configurés dans le kubeconfig du serveur. Vérifier le contexte courant avec `kubectl config current-context` et tester les permissions avec `kubectl auth can-i`.
- **Le Rollout de test n'apparaît pas** : vérifier sa présence et son namespace avec `kubectl get rollouts --all-namespaces`, et vérifier que le contrôleur est opérationnel.
- **Le Rollout reste en pause** : c'est attendu après `pause: {}` ; utiliser `kubectl argo rollouts promote rollout-demo -n default`.
- **Le poids Canary n'est pas un pourcentage exact du trafic** : sans intégration de routage de trafic, le poids est approximé par le nombre de réplicas.