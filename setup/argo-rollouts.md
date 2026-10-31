# Installer Argo Rollouts et accéder au dashboard

Argo Rollouts ajoute à Kubernetes des déploiements progressifs, notamment Canary et Blue-Green. Ce guide installe le contrôleur et le plugin `kubectl`, lance le dashboard depuis la CLI, permet d'y accéder au moyen d'un tunnel SSH, puis vérifie le fonctionnement avec un Rollout Canary de démonstration.

Les commandes supposent que `kubectl` est configuré pour le cluster cible et que l'utilisateur peut créer des ressources cluster-scoped (CRD, rôles et bindings). L'exemple utilise Argo Rollouts **v1.10.1** ; vérifier la compatibilité avec la version Kubernetes du cluster avant une installation différente.

> **Sécurité :** le dashboard n'a pas d'authentification intégrée. Il utilise les identifiants et les permissions Kubernetes de l'utilisateur qui lance la commande. Le tunnel SSH garde le port du dashboard sur la boucle locale : ne pas le lier à `0.0.0.0` et ne pas ouvrir le port `3100` dans le pare-feu ou sur Internet.

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

Dans un second terminal de l'ordinateur, ouvrir le tunnel SSH. Remplacer l'utilisateur et l'adresse publique par ceux du serveur :

```bash
ssh -N -L 3100:127.0.0.1:3100 ubuntu@IP_PUBLIQUE_DU_SERVEUR
```

Garder cette connexion SSH active et ouvrir <http://localhost:3100/rollouts> dans le navigateur. Lorsque la consultation est terminée, fermer le tunnel avec `Ctrl+C`, puis arrêter le dashboard sur le serveur avec `Ctrl+C`.

Le port `3100` n'a pas besoin d'être ouvert dans le pare-feu du serveur ou du fournisseur cloud. Il suffit que SSH soit accessible depuis l'ordinateur d'administration. Si le port local `3100` est déjà utilisé, choisir par exemple `13100` côté ordinateur :

```bash
ssh -N -L 13100:127.0.0.1:3100 ubuntu@IP_PUBLIQUE_DU_SERVEUR
```

Dans ce cas, ouvrir <http://localhost:13100/rollouts>.

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