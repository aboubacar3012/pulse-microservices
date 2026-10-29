# Exposer les applications avec Traefik sur Lightsail

Installe MetalLB et Traefik sur kubeadm pour publier Argo CD, Grafana et d'autres applications avec un domaine.

## 1. Préparer Lightsail et le DNS

Dans **Lightsail → Instance → Networking**, autoriser les ports TCP **80** et **443**.

Récupérer l'IP privée de l'instance :

```bash
hostname -I
```

Le DNS `A` de chaque domaine doit pointer vers l'IP publique Lightsail. Le pool MetalLB utilise l'IP privée. Installer Longhorn avant Traefik pour conserver le fichier ACME : [guide Longhorn](./longhorn/longhorn.md).

## 2. Installer MetalLB

```bash
kubectl apply -f \
  https://raw.githubusercontent.com/metallb/metallb/v0.16.1/config/manifests/metallb-native.yaml
kubectl rollout status deployment/controller -n metallb-system --timeout=180s
kubectl rollout status daemonset/speaker -n metallb-system --timeout=180s
```

Créer le pool MetalLB. Remplacer `172.26.8.148` par l'IP privée de l'instance :

```bash
kubectl apply -f - <<'EOF'
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: traefik-pool
  namespace: metallb-system
spec:
  addresses:
    - 172.26.8.148/32
  autoAssign: false
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: traefik-pool
  namespace: metallb-system
spec:
  ipAddressPools:
    - traefik-pool
EOF
```

## 3. Installer Traefik

Créer `traefik-values.yaml`. Remplacer l'IP et l'adresse e-mail :

```yaml
api:
  dashboard: false

ingressClass:
  enabled: true
  isDefaultClass: false
  name: traefik

providers:
  kubernetesIngress:
    enabled: true
    ingressClass: traefik
  kubernetesCRD:
    enabled: false

service:
  enabled: true
  annotations:
    metallb.io/address-pool: traefik-pool
    metallb.io/loadBalancerIPs: "172.26.8.148"
  spec:
    type: LoadBalancer

persistence:
  enabled: true
  accessMode: ReadWriteOnce
  size: 128Mi
  storageClass: longhorn
  path: /data

additionalArguments:
  - "--certificatesresolvers.le-resolver.acme.email=admin@example.com"
  - "--certificatesresolvers.le-resolver.acme.storage=/data/acme.json"
  - "--certificatesresolvers.le-resolver.acme.httpchallenge.entrypoint=web"
```

Installer et vérifier :

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm upgrade --install traefik traefik/traefik \
  --namespace traefik \
  --create-namespace \
  --values traefik-values.yaml
kubectl get pods,svc -n traefik
kubectl get ingressclass
```

Le service `traefik` doit afficher l'IP privée configurée.

## 4. Ajouter un Ingress

Pour chaque application, créer un DNS `A` pointant vers l'IP publique Lightsail. Créer ensuite un Ingress dans le namespace de son service. Remplacer le domaine, le namespace, le nom et le port du service :

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: application
  namespace: <NAMESPACE>
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.tls.certresolver: le-resolver
spec:
  ingressClassName: traefik
  rules:
    - host: app.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: <NOM-DU-SERVICE>
                port:
                  number: <PORT-DU-SERVICE>
  tls:
    - hosts:
        - app.example.com
```

Pour Grafana de `kube-prometheus-stack`, utiliser le service `monitoring-grafana`, port `80`.

Pour Argo CD, configurer le serveur en HTTP derrière Traefik et utiliser le service `argocd-server`, port `80` :

```bash
kubectl patch configmap argocd-cmd-params-cm -n argocd \
  --type merge -p '{"data":{"server.insecure":"true"}}'
kubectl rollout restart deployment argocd-server -n argocd
```

Appliquer le fichier Ingress et vérifier :

```bash
kubectl apply -f ingress.yaml
kubectl get ingress -A
curl -I https://app.example.com
```

## En cas de problème

- **IP `pending`** : vérifier le pool MetalLB et `kubectl describe svc traefik -n traefik`.
- **Domaine inaccessible** : vérifier le DNS public et l'ouverture des ports 80/443.
- **Pas de certificat** : vérifier que le domaine pointe vers l'IP publique et consulter `kubectl logs deployment/traefik -n traefik`.
- **Ingress 404** : vérifier `ingressClassName`, le domaine, le namespace et le service backend.
- **Traefik bloqué** : vérifier le PVC avec `kubectl get pvc -n traefik`.

## Sécurité

- Ne pas activer ni exposer le dashboard Traefik.
- Garder `isDefaultClass: false` et définir `ingressClassName: traefik` sur les Ingress.
- Garder l'authentification Argo CD et Grafana activée.
- Ne pas ouvrir les NodePorts Traefik directement sur Internet.
- Ne pas committer de mots de passe, tokens ou fichiers secrets.
