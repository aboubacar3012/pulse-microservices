# Configurer un ServiceAccount Kubernetes pour Jenkins

Ce guide décrit comment autoriser Jenkins à déployer les manifests applicatifs d’un namespace avec des permissions RBAC limitées. Il couvre la création du ServiceAccount, la validation de ses permissions, la création d’un kubeconfig et son ajout aux credentials Jenkins.

Sauf indication contraire, exécuter les commandes depuis la racine du dépôt avec `kubectl` déjà configuré sur le cluster cible.

> **Important — durée de vie du token :** `kubectl create token` produit un token à durée limitée. Le cluster peut limiter la durée demandée. Le kubeconfig créé avec ce token finira donc par expirer et devra être renouvelé dans Jenkins. Pour un Jenkins qui tourne dans le cluster, privilégier un ServiceAccount associé directement au pod Jenkins plutôt qu’un kubeconfig contenant un token copié manuellement.

## 1. Choisir le namespace

Les exemples ci-dessous utilisent le namespace `default`, car les manifests Pulse actuels l’utilisent ou s’appuient sur ce namespace par défaut. Si l’application est déployée ailleurs, remplacer `default` partout et vérifier que les manifests ciblent ce même namespace.

Le compte utilisé pour cette configuration doit pouvoir créer des ServiceAccounts, Roles et RoleBindings dans le namespace choisi. Cette opération se fait avec un compte d’administration, pas avec le compte Jenkins à créer.

## 2. Créer le ServiceAccount et lui attribuer les permissions minimales

Créer `jenkins-rbac.yaml` :

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: jenkins-deployer
  namespace: default
automountServiceAccountToken: false
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: jenkins-deployer
  namespace: default
rules:
  # Création, mise à jour et suivi des Deployments.
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "watch", "create", "patch"]
  # Lecture des ReplicaSets créés par les Deployments, nécessaire au suivi du rollout.
  - apiGroups: ["apps"]
    resources: ["replicasets"]
    verbs: ["get", "list", "watch"]
  # Les manifests applicatifs peuvent créer ou modifier Services et ConfigMaps.
  - apiGroups: [""]
    resources: ["services", "configmaps"]
    verbs: ["get", "list", "watch", "create", "patch"]
  # Lecture des Pods et événements pour diagnostiquer les échecs de rollout.
  - apiGroups: [""]
    resources: ["pods", "events"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: jenkins-deployer
  namespace: default
subjects:
  - kind: ServiceAccount
    name: jenkins-deployer
    namespace: default
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: jenkins-deployer
```

Appliquer le fichier avec le compte d’administration :

```bash
kubectl apply --filename jenkins-rbac.yaml
```

Le Role ne donne aucun droit de suppression, aucun accès aux Secrets et aucun droit hors de `default`. Ne pas ajouter l’accès aux Secrets « au cas où ». Si un manifest du dossier `k8s/` crée une autre ressource (Ingress, StatefulSet, Job, etc.), ajouter uniquement les verbes nécessaires sur cette ressource au Role, puis réappliquer le fichier.

Ce Role ne permet pas de créer de namespace ni d’autres ressources globales au cluster. Créer les namespaces au préalable avec un compte d’administration. Pour déployer dans plusieurs namespaces, créer un Role et un RoleBinding pour chacun.

## 3. Vérifier le RBAC avant de créer le kubeconfig

Avec le compte d’administration, vérifier que le ServiceAccount peut effectuer les opérations de déploiement nécessaires :

```bash
kubectl auth can-i create deployments.apps \
  --as=system:serviceaccount:default:jenkins-deployer \
  --namespace=default

kubectl auth can-i patch deployments.apps \
  --as=system:serviceaccount:default:jenkins-deployer \
  --namespace=default

kubectl auth can-i watch deployments.apps \
  --as=system:serviceaccount:default:jenkins-deployer \
  --namespace=default
```

Chaque commande doit répondre `yes`. Si elles répondent `no`, vérifier le namespace du ServiceAccount, du Role et du RoleBinding, ainsi que le sujet et le rôle référencés dans le RoleBinding.

Les vérifications avec `--as` nécessitent que le compte d’administration soit autorisé à impersonner ce ServiceAccount. Si cette permission n’est pas disponible, passer directement aux tests de l’étape 5 avec le kubeconfig Jenkins.

La simulation serveur, effectuée à l’étape 5 avec le kubeconfig Jenkins, validera également les manifests et les permissions réelles avant toute modification du cluster.

## 4. Générer un kubeconfig pour Jenkins

Les versions récentes de Kubernetes ne créent plus automatiquement un Secret avec token lors de la création d’un ServiceAccount. Générer un token avec TokenRequest :

```bash
TOKEN=$(kubectl create token jenkins-deployer \
  --namespace=default \
  --duration=24h)
APISERVER=$(kubectl config view --minify \
  --output=jsonpath='{.clusters[0].cluster.server}')
CA_DATA=$(kubectl config view --raw --minify \
  --output=jsonpath='{.clusters[0].cluster.certificate-authority-data}')
```

La durée effective peut être inférieure à celle demandée, selon la configuration du cluster. Ne pas afficher ni publier le token, ni l’envoyer dans un journal de build, un dépôt Git ou un ticket. Les commandes ci-dessus le conservent uniquement dans la variable de la session shell le temps de créer le kubeconfig.

Vérifier que l’adresse et le certificat ne sont pas vides :

```bash
test -n "$TOKEN" && test -n "$APISERVER" && test -n "$CA_DATA"
```

Créer `jenkins-kubeconfig.yaml` à la racine du dépôt :

```bash
umask 077
cat > jenkins-kubeconfig.yaml <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: jenkins-cluster
    cluster:
      server: ${APISERVER}
      certificate-authority-data: ${CA_DATA}
contexts:
  - name: jenkins-context
    context:
      cluster: jenkins-cluster
      namespace: default
      user: jenkins-deployer
current-context: jenkins-context
users:
  - name: jenkins-deployer
    user:
      token: ${TOKEN}
EOF
unset TOKEN
```

`umask 077` limite la lecture du fichier au compte qui l’a créé. Si `CA_DATA` est vide, le kubeconfig courant ne contient probablement pas de certificat CA embarqué; ne pas contourner le contrôle TLS avec `insecure-skip-tls-verify`. Récupérer la CA du cluster par le canal d’administration approprié et l’ajouter au kubeconfig.

Le kubeconfig contient un secret. Ne pas le committer. Après l’avoir importé dans Jenkins, supprimer la copie locale de manière sécurisée conformément aux règles de gestion des secrets de l’environnement.

## 5. Tester avec le kubeconfig Jenkins

Vérifier les droits du compte représenté par le kubeconfig :

```bash
kubectl --kubeconfig=jenkins-kubeconfig.yaml auth can-i create deployments.apps \
  --namespace=default

kubectl --kubeconfig=jenkins-kubeconfig.yaml auth can-i patch deployments.apps \
  --namespace=default

kubectl --kubeconfig=jenkins-kubeconfig.yaml auth can-i watch deployments.apps \
  --namespace=default
```

Ces commandes doivent répondre `yes`. Vérifier ensuite les manifests sans les appliquer :

```bash
cd pulse/worker
kubectl --kubeconfig=../../jenkins-kubeconfig.yaml \
  apply --recursive --dry-run=server --validate=strict --filename k8s/
```

La simulation serveur contacte l’API Kubernetes, valide les schémas et vérifie les permissions sans persister les objets. Elle peut échouer si le kubeconfig ne peut pas joindre le cluster ou si le compte ne possède pas tous les droits nécessaires.

Pour tester la ressource et le suivi du rollout :

```bash
kubectl --kubeconfig=../../jenkins-kubeconfig.yaml \
  get --filename k8s/deployment.yaml --output=name
```

Le test ci-dessus lit le Deployment; il ne déclenche pas de déploiement. Le script `k8s.sh` applique ensuite tous les manifests sous `k8s/` et redémarre le Deployment worker.

## 6. Ajouter le kubeconfig dans Jenkins

Dans Jenkins :

1. Ouvrir **Manage Jenkins → Credentials** et choisir le domaine approprié (par exemple **System → Global credentials**).
2. Sélectionner **Add Credentials**.
3. Choisir **Kind: Secret file**.
4. Importer `jenkins-kubeconfig.yaml`.
5. Donner l’ID `kubeconfig`, qui correspond à `withKubeConfig([credentialsId: 'kubeconfig'])` dans le Jenkinsfile du worker.
6. Enregistrer.

Le compte du job Jenkins doit avoir le droit d’utiliser ce credential. Les secrets ne doivent jamais être affichés par le Jenkinsfile.

## 7. Exécuter le déploiement depuis Jenkins

Le stage Kubernetes doit :

1. S’exécuter après le build et la publication de l’image.
2. Charger le credential avec `withKubeConfig`.
3. Se placer dans le répertoire du microservice afin que le chemin `k8s/` existe.
4. Lancer `k8s.sh`, puis `k8s-rollout-status.sh` dans cet ordre.

Les commandes doivent rester séquentielles : le contrôle du rollout ne doit pas démarrer en parallèle de l’application des manifests. Le script d’application réalise un dry-run client, un dry-run serveur puis l’application réelle; le script de statut vérifie l’existence du Deployment et attend le rollout et la condition `Available`.

Si le token expire, les commandes `kubectl` échoueront avec une erreur d’authentification. Générer un nouveau token et remplacer le fichier credential Jenkins avant de relancer le job. Pour un usage durable, mettre en place une stratégie de renouvellement ou préférer l’identité Kubernetes du pod Jenkins avec un mécanisme d’authentification adapté à l’environnement.
