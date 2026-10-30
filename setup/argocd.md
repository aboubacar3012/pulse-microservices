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
kubectl get configmap argocd-cmd-params-cm -n argocd \
  -o jsonpath='{.data.server\.insecure}'; echo
```

La dernière commande doit afficher `true`. Ce réglage désactive TLS **entre Traefik et Argo CD uniquement**; Traefik termine toujours la connexion HTTPS publique.

Créer `argocd-ingress.yaml` et remplacer `gitops-practices-argocd.santu.io` par votre domaine :

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
    - host: gitops-practices-argocd.santu.io
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
        - gitops-practices-argocd.santu.io
```

Appliquer et vérifier :

```bash
kubectl apply -f argocd-ingress.yaml
kubectl get ingress -n argocd
```

Ouvrir `https://gitops-practices-argocd.santu.io`. Si l'Ingress fonctionne, remettre le service en `ClusterIP` pour ne plus l'exposer aussi par NodePort :

```bash
kubectl patch service argocd-server -n argocd \
  --type merge -p '{"spec":{"type":"ClusterIP"}}'
kubectl get service argocd-server -n argocd
```

## Dépannage de l'accès via Traefik

Vérifier d'abord que les pods et services sont prêts et que l'Ingress cible bien le service Argo CD :

```bash
kubectl get pods -n traefik -o wide
kubectl get service traefik -n traefik -o wide
kubectl get ingress argocd-server -n argocd -o wide
kubectl describe ingress argocd-server -n argocd
kubectl get service argocd-server -n argocd
kubectl get endpointslice -n argocd \
  -l kubernetes.io/service-name=argocd-server
kubectl get configmap argocd-cmd-params-cm -n argocd \
  -o jsonpath='{.data.server\.insecure}'; echo
```

Le service Traefik doit avoir une adresse externe, l'Ingress doit afficher la bonne classe et le bon nom d'hôte, et l'EndpointSlice Argo CD doit contenir au moins une adresse. Le service `argocd-server` doit être en `ClusterIP` pour l'accès par Ingress.

Consulter les événements et les journaux si l'un de ces éléments n'est pas prêt :

```bash
kubectl get events -n traefik --sort-by=.lastTimestamp
kubectl get events -n argocd --sort-by=.lastTimestamp
kubectl logs deployment/traefik -n traefik --since=10m
kubectl logs deployment/argocd-server -n argocd --since=10m
```

Tester le routage depuis le nœud ou une machine qui peut joindre l'adresse privée MetalLB :

```bash
curl -vk --connect-timeout 5 \
  --resolve gitops-practices-argocd.santu.io:443:172.26.3.27 \
  https://gitops-practices-argocd.santu.io/
```

Une réponse `200` confirme le routage HTTPS interne jusqu'à Argo CD. Pour vérifier l'accès public à l'origine sans passer par le DNS Cloudflare, lancer depuis une machine **hors du serveur** la même commande en remplaçant `172.26.3.27` par l'adresse IPv4 publique de Lightsail. Vérifier également que :

- le DNS public du domaine pointe vers l'adresse IPv4 publique de Lightsail (de préférence une IP statique), pas vers l'adresse privée MetalLB;
- les règles réseau Lightsail autorisent les connexions entrantes TCP sur les ports `443` et `80`;
- le port `443` est ouvert, car le navigateur se connecte en HTTPS.

Si le test interne répond mais que le test externe échoue, vérifier le DNS, l'adresse publique et les règles réseau Lightsail. Une erreur Cloudflare `522` indique que Cloudflare n'obtient pas de réponse de l'origine; le patch `server.insecure` ne configure ni le DNS ni le pare-feu.
