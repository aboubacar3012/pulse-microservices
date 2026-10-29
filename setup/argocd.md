# Installer et accéder à Argo CD

## 1. Installer Argo CD

Créer le namespace et installer les manifests officiels :

```bash
kubectl create namespace argocd
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Attendre que les composants soient prêts :

```bash
kubectl wait --for=condition=available deployment --all \
  -n argocd --timeout=300s
kubectl get pods -n argocd
```

## 2. Accéder avec un NodePort

Exposer le service Argo CD en NodePort :

```bash
kubectl patch service argocd-server -n argocd \
  --type merge -p '{"spec":{"type":"NodePort"}}'
kubectl get service argocd-server -n argocd
```

Récupérer le port HTTPS attribué :

```bash
kubectl get service argocd-server -n argocd \
  -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}'; echo
```

Ouvrir ce port TCP dans le pare-feu du serveur, de préférence uniquement pour les adresses IP autorisées. Accéder à l'interface à l'adresse :

```text
https://<IP-DU-NOEUD>:<NODEPORT-HTTPS>
```

Récupérer le mot de passe admin initial :

```bash
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 --decode; echo
```

Se connecter avec l'utilisateur `admin`, puis changer le mot de passe.

## Option — Accéder avec un Ingress Traefik

Cette option suppose que Traefik fonctionne déjà dans le cluster, avec un résolveur TLS configuré, et que le DNS du domaine pointe vers l'adresse publique du cluster.

Configurer Argo CD pour accepter le HTTP depuis Traefik. Le trafic entre le navigateur et Traefik reste en HTTPS :

```bash
kubectl patch configmap argocd-cmd-params-cm -n argocd \
  --type merge -p '{"data":{"server.insecure":"true"}}'
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout status deployment argocd-server -n argocd --timeout=300s
```

Créer `argocd-ingress.yaml` et remplacer `argocd.example.com` par votre domaine :

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
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

Appliquer et vérifier :

```bash
kubectl apply -f argocd-ingress.yaml
kubectl get ingress -n argocd
```

Ouvrir `https://argocd.example.com`. Si l'Ingress fonctionne, remettre le service en `ClusterIP` pour ne plus l'exposer aussi par NodePort :

```bash
kubectl patch service argocd-server -n argocd \
  --type merge -p '{"spec":{"type":"ClusterIP"}}'
```
