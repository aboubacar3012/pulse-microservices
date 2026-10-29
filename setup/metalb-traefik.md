# Publier ArgoCD, Grafana et les applications avec Traefik

Cette procédure installe MetalLB et Traefik sur un cluster kubeadm. Traefik reçoit une IP privée via MetalLB; les requêtes des domaines publics arrivent sur l'IP publique de l'instance Lightsail, puis sont routées vers les Ingress du cluster.

Le guide part du montage Lightsail déjà utilisé dans ce lab. Il faut remplacer les IP et noms de domaine d'exemple par ceux de votre instance.

## 1. Préparer Lightsail et le cluster

Dans **Lightsail → Instance → Networking**, autoriser :

| Port | Protocole | Usage |
|---|---|---|
| 80 | TCP | Challenge HTTP Let's Encrypt |
| 443 | TCP | Accès HTTPS aux Ingress |

Le DNS public de chaque application doit pointer vers l'**IP publique** de l'instance Lightsail. Le pool MetalLB, lui, utilise l'**IP privée** de l'instance.

Vérifier l'IP privée sur l'instance :

```bash
hostname -I
```

Noter l'adresse privée utilisée par le cluster, puis utiliser exactement cette même adresse dans le pool MetalLB et dans les annotations Traefik ci-dessous.

Pour le stockage du fichier de certificats ACME, installer d'abord Longhorn en suivant [`longhorn.md`](./longhorn/longhorn.md). Le StorageClass `longhorn` sera utilisé par Traefik.

## 2. Installer MetalLB

```bash
kubectl apply -f \
  https://raw.githubusercontent.com/metallb/metallb/v0.16.1/config/manifests/metallb-native.yaml

kubectl rollout status deployment/controller \
  -n metallb-system --timeout=180s
kubectl rollout status daemonset/speaker \
  -n metallb-system --timeout=180s
```

Créer le pool avec l'IP privée de l'instance. Remplacer `172.26.8.148` par l'adresse trouvée à l'étape 1 :

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

Créer `traefik-values.yaml`. Remplacer :

- `172.26.8.148` par l'IP privée utilisée dans le pool MetalLB ;
- `admin@example.com` par une adresse e-mail valide.

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

Installer Traefik :

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm upgrade --install traefik traefik/traefik \
  --namespace traefik \
  --create-namespace \
  --values traefik-values.yaml
```

Vérifier que le Service Traefik a reçu l'IP privée :

```bash
kubectl get pods,svc -n traefik
kubectl get ingressclass
```

Le Service `traefik` doit être `LoadBalancer` et afficher l'IP privée dans `EXTERNAL-IP`.

## 4. Créer un Ingress pour chaque application

Pour chaque application :

1. Créer un enregistrement DNS `A` pour son domaine, pointant vers l'IP publique Lightsail.
2. Créer un Ingress dans le même namespace que le Service de l'application.
3. Renseigner `ingressClassName: traefik`, le nom du domaine, le Service et son port.

Exemple pour Grafana installé par `kube-prometheus-stack` avec la release `monitoring` :

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana
  namespace: monitoring
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.tls.certresolver: le-resolver
spec:
  ingressClassName: traefik
  rules:
    - host: grafana.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: monitoring-grafana
                port:
                  number: 80
  tls:
    - hosts:
        - grafana.example.com
```

Exemple pour ArgoCD configuré en HTTP derrière Traefik (`server.insecure: "true"`) :

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd
  namespace: argocd
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.tls.certresolver: le-resolver
spec:
  ingressClassName: traefik
  rules:
    - host: argocd.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  number: 80
  tls:
    - hosts:
        - argocd.example.com
```

Remplacer `example.com` par votre domaine. Répéter le même modèle pour les autres applications en adaptant le namespace, le nom/port du Service et le domaine.

Appliquer chaque Ingress et vérifier :

```bash
kubectl apply -f ingress.yaml
kubectl get ingress -A
kubectl describe ingress grafana -n monitoring
```

Traefik détecte automatiquement les Ingress avec `ingressClassName: traefik`. Let's Encrypt émet le certificat si le domaine résout correctement vers Lightsail et si le port 80 est joignable depuis Internet.

## Vérification rapide

```bash
kubectl get svc traefik -n traefik
kubectl get ingress -A
kubectl logs deployment/traefik -n traefik | grep -iE 'acme|error'
```

Tester un domaine :

```bash
curl -I https://grafana.example.com
```

## En cas de problème

| Problème | Vérification |
|---|---|
| `EXTERNAL-IP` reste `pending` | `kubectl describe svc traefik -n traefik` et `kubectl logs -n metallb-system deployment/controller` ; vérifier que l'IP dans le pool correspond à celle demandée par Traefik. |
| Domaine inaccessible | Vérifier que le DNS `A` pointe vers l'IP publique Lightsail et que TCP/80 et TCP/443 sont autorisés. |
| Certificat absent | Vérifier que le domaine est public, que TCP/80 est joignable et consulter les logs Traefik. |
| Ingress retourne 404 | Vérifier `ingressClassName`, le domaine, le namespace, et le nom/port du Service backend. |
| Pod Traefik reste `Pending` | Vérifier que le PVC est `Bound` et que le StorageClass `longhorn` existe. |

## Sécurité

- Ne pas exposer le dashboard Traefik.
- Conserver `isDefaultClass: false` et définir `ingressClassName: traefik` dans chaque Ingress.
- Garder Grafana et ArgoCD protégés par leur authentification; HTTPS seul ne remplace pas l'authentification.
- Ne pas ouvrir les NodePorts Traefik directement sur Internet.
- Ne pas committer de mots de passe, tokens ou fichiers contenant des secrets.

Documentation : [Traefik Helm chart](https://github.com/traefik/traefik-helm-chart), [MetalLB](https://metallb.io/installation/), [Longhorn](./longhorn/longhorn.md).
