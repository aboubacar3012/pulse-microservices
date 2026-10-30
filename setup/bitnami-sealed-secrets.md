# Stocker des secrets Kubernetes avec Sealed Secrets

Sealed Secrets chiffre un Secret Kubernetes pour pouvoir versionner son manifeste chiffré dans un dépôt Git (GitOps). Le contrôleur du cluster déchiffre le `SealedSecret` et crée le Secret Kubernetes correspondant.

Le principe est le même pour les mots de passe, clés API, fichiers de configuration, certificats TLS ou identifiants de registry. Le manifeste en clair ne doit jamais être committé ni partagé.

Les clés privées de chiffrement du contrôleur sont nécessaires pour déchiffrer les Sealed Secrets existants après une restauration ou une migration du cluster. Les sauvegarder de manière sécurisée, séparément du dépôt Git, et ne jamais les partager.

## 1. Installer le contrôleur dans le cluster

Appliquer le manifeste officiel versionné :

```bash
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.3/controller.yaml
```

Attendre que le contrôleur soit prêt :

```bash
kubectl rollout status deployment/sealed-secrets-controller \
  --namespace kube-system \
  --timeout=180s
kubectl get pods --namespace kube-system \
  -l name=sealed-secrets-controller
```

## 2. Installer `kubeseal` sur la machine d'administration

Cette commande installe la version Linux amd64. Pour un autre système ou une autre architecture, télécharger l'archive correspondante depuis la page des [versions de Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets/releases).

```bash
KUBESEAL_VERSION='0.27.3'
curl -OL "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz"
tar -xzf "kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz" kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
rm "kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz" kubeseal
```

Vérifier que `kubeseal` peut récupérer le certificat public du contrôleur :

```bash
kubeseal --fetch-cert
```

Si la commande indique que le service `sealed-secrets-controller` est introuvable, vérifier le nom et le namespace réels :

```bash
kubectl get services --all-namespaces | grep -i sealed
```

Puis préciser ceux-ci avec les options `--controller-name` et `--controller-namespace` dans les commandes `kubeseal`.

## 3. Créer et chiffrer un Secret

Un Secret Kubernetes est propre à un namespace. Définir le namespace et le nom du Secret à créer. L'exemple utilise `development` et `app-credentials` ; les remplacer par les valeurs adaptées :

```bash
NAMESPACE=development
SECRET_NAME=app-credentials
kubectl get namespace "$NAMESPACE"
```

Les commandes suivantes illustrent un Secret générique contenant deux clés. Remplacer les noms de clés et les valeurs d'exemple par ceux requis par l'application :

```bash
umask 077
kubectl create secret generic "$SECRET_NAME" \
  --from-literal=username='REMPLACER_PAR_LA_VALEUR' \
  --from-literal=password='REMPLACER_PAR_LA_VALEUR' \
  --namespace="$NAMESPACE" \
  --dry-run=client -o yaml > secret-plain.yaml
```

`--from-literal` convient à des valeurs simples, mais la valeur saisie peut être conservée dans l'historique du shell. Pour des secrets réels, privilégier une saisie interactive ou des fichiers locaux protégés et exclus de Git. Ne jamais coller de vrai secret dans un terminal partagé ou dans une commande enregistrée.

Pour créer un Secret à partir de fichiers, utiliser une option `--from-file` pour chaque clé. Les fichiers sources doivent rester locaux et ne pas être committés :

```bash
kubectl create secret generic "$SECRET_NAME" \
  --from-file=username=./username.txt \
  --from-file=./app-credential.txt \
  --namespace="$NAMESPACE" \
  --dry-run=client -o yaml > secret-plain.yaml
```

Avec `--from-file=./app-credential.txt`, le nom du fichier devient la clé `app-credential.txt`. Utiliser `--from-file=nom-de-cle=chemin-du-fichier` pour choisir explicitement une clé.

Chiffrer le manifeste. Par défaut, le chiffrement est lié au nom et au namespace du Secret : conserver ces valeurs dans le manifeste final.

```bash
kubeseal --format yaml < secret-plain.yaml > secret-sealed.yaml &&
  rm secret-plain.yaml &&
kubectl apply -f secret-sealed.yaml
```

La suppression du manifeste en clair n'a lieu qu'après un chiffrement réussi.

Le fichier `secret-sealed.yaml` peut être versionné. Vérifier qu'aucun fichier en clair, fichier source ou valeur secrète n'est ajouté au dépôt.

## 4. Vérifier le Sealed Secret

Vérifier que le contrôleur a créé le Secret dans le namespace attendu :

```bash
NAMESPACE=development
SECRET_NAME=app-credentials
kubectl get sealedsecret "$SECRET_NAME" --namespace "$NAMESPACE"
kubectl describe sealedsecret "$SECRET_NAME" --namespace "$NAMESPACE"
kubectl get secret "$SECRET_NAME" --namespace "$NAMESPACE"
```

Pour vérifier le type sans afficher le contenu du Secret :

```bash
kubectl get secret "$SECRET_NAME" --namespace "$NAMESPACE" \
  -o jsonpath='{.type}'; echo
```

Un Secret générique a généralement le type `Opaque`. Ne pas afficher ni décoder `.data` dans un terminal, des logs ou une capture d'écran : les valeurs encodées en base64 ne sont pas chiffrées.

Si le Secret enfant n'apparaît pas, consulter les événements du namespace et les logs du contrôleur :

```bash
kubectl get events --namespace "$NAMESPACE" --sort-by=.lastTimestamp
kubectl logs deployment/sealed-secrets-controller \
  --namespace kube-system \
  --since=10m
```

## 5. Exemple optionnel — certificat TLS

Pour stocker un certificat et sa clé privée avec le type Kubernetes adapté, créer un Secret TLS. Les fichiers doivent rester locaux et être exclus de Git :

```bash
kubectl create secret tls app-tls \
  --cert=./tls.crt \
  --key=./tls.key \
  --namespace="$NAMESPACE" \
  --dry-run=client -o yaml > secret-plain.yaml
```

Chiffrer et appliquer ce manifeste comme à la section 3, puis vérifier que son type est `kubernetes.io/tls` sans afficher son contenu.

## 6. Exemple optionnel — identifiants du registry GitLab

Pour autoriser Kubernetes à récupérer une image privée sur le registry GitLab, créer un Deploy Token :

1. Dans GitLab, ouvrir **Project → Settings → Repository → Deploy tokens**.
2. Cliquer sur **Add token** et choisir un nom, par exemple `k8s-dev-registry-pull`.
3. Sélectionner uniquement le scope `read_registry`.
4. Générer le token et conserver ses identifiants dans un gestionnaire de secrets.

Saisir les identifiants de manière interactive, puis générer le Secret de type Docker. La saisie masquée évite d'inscrire le token dans l'historique du shell. Ne pas exécuter ces commandes avec la trace shell activée (`set -x`).

```bash
read -r -p 'Nom du Deploy Token : ' DOCKER_USERNAME
read -r -s -p 'Valeur du Deploy Token : ' DOCKER_PASSWORD
echo
umask 077
kubectl create secret docker-registry k8s-dev-registry-pull \
  --docker-server=registry.gitlab.com \
  --docker-username="$DOCKER_USERNAME" \
  --docker-password="$DOCKER_PASSWORD" \
  --namespace=development \
  --dry-run=client -o yaml > secret-plain.yaml &&
  kubeseal --format yaml < secret-plain.yaml > secret-sealed.yaml &&
  rm secret-plain.yaml &&
  kubectl apply -f secret-sealed.yaml
unset DOCKER_PASSWORD DOCKER_USERNAME
```

Vérifier le type sans révéler les identifiants :

```bash
kubectl get secret k8s-dev-registry-pull --namespace development \
  -o jsonpath='{.type}'; echo
```

Le résultat attendu est `kubernetes.io/dockerconfigjson`.

Tester ensuite le secret en demandant à un Pod de récupérer une image privée. Remplacer l'image par une image et un tag auxquels le token a accès :

```bash
kubectl run test-pull --namespace development \
  --image='registry.gitlab.com/GROUPE/PROJET/IMAGE:TAG' \
  --overrides='{"spec":{"imagePullSecrets":[{"name":"k8s-dev-registry-pull"}]}}' \
  --restart=Never
```

Examiner l'état du Pod et ses événements :

```bash
kubectl describe pod test-pull --namespace development
```

- `Successfully pulled image` indique que le téléchargement a réussi.
- `ErrImagePull`, `ImagePullBackOff` ou `unauthorized` indique généralement un problème d'accès à l'image, de token ou de scope.

Supprimer le Pod de test après vérification :

```bash
kubectl delete pod test-pull --namespace development
```

## 7. Supprimer ou recréer un Sealed Secret

Pour supprimer le Secret généré par un Sealed Secret, supprimer le `SealedSecret` parent :

```bash
NAMESPACE=development
SECRET_NAME=app-credentials
kubectl get sealedsecret "$SECRET_NAME" --namespace "$NAMESPACE"
kubectl delete sealedsecret "$SECRET_NAME" --namespace "$NAMESPACE"
```

Le contrôleur supprime normalement le Secret enfant associé. Cette suppression peut interrompre les applications qui en dépendent. Vérifier l'état des deux ressources :

```bash
kubectl get sealedsecret,secret "$SECRET_NAME" --namespace "$NAMESPACE"
```

Pour recréer le secret ou modifier une de ses valeurs, générer un nouveau manifeste en clair, le chiffrer avec `kubeseal`, supprimer le fichier en clair, puis appliquer et vérifier le nouveau manifeste. Ne pas supprimer un Secret utilisé par une application en production sans prévoir son remplacement.
