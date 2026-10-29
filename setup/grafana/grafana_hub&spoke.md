# Grafana et Prometheus — Hub & Spoke

Prometheus collecte les métriques sur le Spoke; Grafana sur le Hub les affiche. Pour une installation sur un seul cluster, voir [le guide tout-en-un](./grafana_all_in_one.md).

## 1. Préparer les clusters

- Configurer `kubectl` sur le cluster Spoke, puis sur le Hub au moment des commandes correspondantes.
- Installer Longhorn sur le Spoke : [guide Longhorn](../longhorn/longhorn.md).
- Dans Lightsail, placer Hub et Spoke dans la même région. Le Hub doit pouvoir joindre l'IP privée du Spoke sur TCP/32090.

## 2. Installer Prometheus sur le Spoke

Créer `spoke-values.yaml` :

```yaml
grafana:
  enabled: false

prometheus:
  service:
    type: NodePort
    nodePort: 32090
  prometheusSpec:
    retention: 3d
    resources:
      requests:
        memory: 400Mi
        cpu: 200m
      limits:
        memory: 800Mi
        cpu: 500m
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: longhorn
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 5Gi

alertmanager:
  alertmanagerSpec:
    resources:
      requests:
        memory: 50Mi
      limits:
        memory: 100Mi

nodeExporter:
  resources:
    requests:
      memory: 30Mi

kubeStateMetrics:
  resources:
    requests:
      memory: 50Mi
```

Installer :

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values spoke-values.yaml
```

Vérifier le service et autoriser TCP/32090 dans le pare-feu du Spoke. Limiter l'accès à l'IP du Hub si possible :

```bash
kubectl get pods,svc,pvc -n monitoring
hostname -I | awk '{print $1}'
```

Noter l'IP privée du Spoke.

## 3. Installer Grafana sur le Hub

Créer le namespace et le Secret admin. Saisir le mot de passe lorsqu'il est demandé :

```bash
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
read -r -s -p "Mot de passe admin Grafana : " GRAFANA_ADMIN_PASSWORD
printf '\n'
kubectl create secret generic grafana-admin -n monitoring \
  --from-literal=admin-password="$GRAFANA_ADMIN_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -
unset GRAFANA_ADMIN_PASSWORD
```

Créer `grafana.yaml` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: grafana
  template:
    metadata:
      labels:
        app: grafana
    spec:
      containers:
        - name: grafana
          image: grafana/grafana:11.3.0
          ports:
            - name: http
              containerPort: 3000
          env:
            - name: GF_SECURITY_ADMIN_USER
              value: admin
            - name: GF_SECURITY_ADMIN_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: grafana-admin
                  key: admin-password
          resources:
            requests:
              memory: 100Mi
              cpu: 100m
            limits:
              memory: 200Mi
              cpu: 200m
---
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: monitoring
spec:
  type: NodePort
  selector:
    app: grafana
  ports:
    - name: http
      port: 3000
      targetPort: http
      nodePort: 32000
```

Appliquer et vérifier :

```bash
kubectl apply -f grafana.yaml
kubectl get pods,svc -n monitoring
```

Autoriser TCP/32000 dans le pare-feu du Hub, idéalement uniquement depuis les IP autorisées. Ouvrir `http://<IP-PUBLIQUE-HUB>:32000` et se connecter avec `admin` et le mot de passe choisi.

## 4. Connecter Grafana à Prometheus

Dans Grafana : **Connections → Data sources → Add data source → Prometheus**. Saisir :

```text
http://<IP-PRIVEE-SPOKE>:32090
```

Cliquer sur **Save & test**. Le résultat doit indiquer que la source de données est connectée.

## Option — Persister les données Grafana

Installer Longhorn sur le Hub, puis ajouter ce PVC dans `grafana.yaml` :

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: grafana-data
  namespace: monitoring
spec:
  storageClassName: longhorn
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 2Gi
```

Dans le Deployment, ajouter sous `spec.template.spec` :

```yaml
      volumes:
        - name: grafana-storage
          persistentVolumeClaim:
            claimName: grafana-data
```

Et sous le conteneur Grafana :

```yaml
          volumeMounts:
            - name: grafana-storage
              mountPath: /var/lib/grafana
```

Appliquer de nouveau `grafana.yaml`.

## Option — Accéder avec un Ingress Traefik

Traefik doit déjà fonctionner sur le Hub avec un résolveur TLS. Voir le [guide Traefik](../metalb-traefik.md). Remplacer le Service NodePort par `type: ClusterIP`, puis ajouter cet Ingress à `grafana.yaml` :

```yaml
---
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
                name: grafana
                port:
                  number: 3000
  tls:
    - hosts:
        - grafana.example.com
```

Créer un enregistrement DNS `A` vers l'adresse publique du Hub, appliquer `grafana.yaml` et ouvrir `https://grafana.example.com`.
