# Grafana et Prometheus — Hub & Spoke

Prometheus tourne sur le cluster Spoke; Grafana tourne sur le Hub.

> Pour installer Grafana et Prometheus **ensemble** sur un seul cluster, suivre plutôt [`grafana_all_in_one.md`](./grafana_all_in_one.md).

---

## Prérequis

```bash
kubectl get storageclass
```

Installer Longhorn sur le Spoke en suivant [`longhorn.md`](../longhorn/longhorn.md). Le StorageClass `longhorn` doit être disponible.

Ressources de départ pour le lab :

| Serveur | Instance Lightsail min. | Rôle                   |
| ------- | ----------------------- | ---------------------- |
| Spoke   | 2 GB RAM                | Prometheus + exporters |
| Hub     | 1 GB RAM                | Grafana seul           |

Le Hub doit joindre l'IP privée du Spoke sur TCP/32090. Utiliser des instances Lightsail dans la même région.

---

## 1. Installer Prometheus sur le Spoke

Sur le Spoke, configurer `kubectl` pour viser le cluster à surveiller.

### Fichier de valeurs Spoke

Créer `spoke-values.yaml` :

```yaml
grafana:
  enabled: false           # Grafana est sur le Hub, pas ici

prometheus:
  service:
    type: NodePort
    nodePort: 32090        # Port fixe — plus fiable qu'un port aléatoire
  prometheusSpec:
    retention: 3d
    resources:
      requests:
        memory: "400Mi"
        cpu: "200m"
      limits:
        memory: "800Mi"
        cpu: "500m"
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
        memory: "50Mi"
      limits:
        memory: "100Mi"

nodeExporter:
  resources:
    requests:
      memory: "30Mi"

kubeStateMetrics:
  resources:
    requests:
      memory: "50Mi"
```

### Installation

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values spoke-values.yaml
```

Vérifier :

```bash
kubectl get pods -n monitoring
kubectl get svc -n monitoring | grep prometheus
```

Le pod `prometheus-kube-prometheus-prometheus-0` doit être en `Running`. Le service doit afficher le NodePort `32090`.

### Ouvrir le port dans le pare-feu Lightsail (Spoke)

> **Console Lightsail → Instance Spoke → Networking → Add rule → TCP → 32090**

> ⚠️ **Sécurité.** Prometheus n'est pas authentifié par défaut. Idéalement, restreindre la règle de pare-feu à l'**IP privée du Hub uniquement**. Si Lightsail ne permet pas de filtrer par IP source dans les règles, s'assurer que les deux instances sont sur le même réseau privé Lightsail et utiliser l'**IP privée** du Spoke dans Grafana (pas l'IP publique).

Relever l'URL Prometheus qui sera utilisée depuis le Hub :

```bash
# IP privée du Spoke (à utiliser de préférence si même région Lightsail)
hostname -I | awk '{print $1}'
# → URL Prometheus : http://<IP-privée-Spoke>:32090
```

---

## 2. Installer Grafana sur le Hub

Se connecter au Hub. Configurer `kubectl` pour viser le cluster du Hub.

### Créer le namespace et le Secret admin

```bash
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

read -r -s -p "Choisir le mot de passe admin Grafana : " GRAFANA_ADMIN_PASSWORD
printf '\n'
kubectl create secret generic grafana-admin \
  --namespace monitoring \
  --dry-run=client \
  --from-literal=admin-password="$GRAFANA_ADMIN_PASSWORD" \
  --output yaml | kubectl apply -f -
unset GRAFANA_ADMIN_PASSWORD
```

> Ne versionner jamais ce Secret dans Git.

### Manifest Grafana — NodePort (défaut)

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
          image: grafana/grafana:11.3.0    # Épingler une version stable, ne pas utiliser :latest
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
              memory: "100Mi"
              cpu: "100m"
            limits:
              memory: "200Mi"
              cpu: "200m"
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

Appliquer :

```bash
kubectl apply -f grafana.yaml
kubectl -n monitoring get pods,svc
```

Attendre que le pod soit `Running`.

### Ouvrir le port dans le pare-feu Lightsail (Hub)

> **Console Lightsail → Instance Hub → Networking → Add rule → TCP → 32000**

Accéder à Grafana : **http://\<IP-publique-Hub\>:32000**

Se connecter avec `admin` et le mot de passe défini dans le Secret.

---

## 3. Ajouter Prometheus comme source de données

1. Dans Grafana, aller dans **Connections > Data Sources**.
2. Cliquer sur **Add data source** → choisir **Prometheus**.
3. Dans **Prometheus server URL**, saisir l'URL relevée à l'étape 1 :
   ```
   http://<IP-privée-Spoke>:32090
   ```
4. Cliquer sur **Save & test**.
   - ✅ Message vert "Data source connected" → tout fonctionne.
   - ❌ Erreur → voir la section Troubleshooting.

---

## 4. Importer des dashboards Kubernetes

1. Ouvrir **Dashboards > New > Import**.
2. Saisir l'ID dans **Import via grafana.com**, cliquer sur **Load**.
3. Sélectionner la source de données Prometheus ajoutée.
4. Cliquer sur **Import**.

Dashboards recommandés pour démarrer :

| Dashboard                       | ID      | Ce qu'il affiche             |
| ------------------------------- | ------- | ---------------------------- |
| Kubernetes / Views / Global     | `15757` | Vue d'ensemble cluster       |
| Kubernetes / Views / Nodes      | `15760` | État et ressources des nœuds |
| Kubernetes / Views / Namespaces | `15758` | Activité par namespace       |
| Kubernetes / Views / Pods       | `15759` | État et ressources par pod   |

Si les graphiques restent vides : vérifier que Prometheus est `UP` dans **Status > Targets** (`http://<IP-privée-Spoke>:32090/targets`) et que la bonne source de données est sélectionnée.

---

## Persister les données Grafana (optionnel)

Installer Longhorn sur le Hub en suivant [`longhorn.md`](../longhorn/longhorn.md), puis ajouter ce PVC dans `grafana.yaml` :

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

Et ajouter dans le `Deployment`, sous `spec.template.spec` :

```yaml
      volumes:
        - name: grafana-storage
          persistentVolumeClaim:
            claimName: grafana-data
      containers:
        - name: grafana
          # ... (existant)
          volumeMounts:
            - name: grafana-storage
              mountPath: /var/lib/grafana
```

---

## Option — Ingress avec Traefik + TLS (accès par domaine)

> Nécessite Traefik installé sur le Hub et un domaine DNS configuré.

Remplacer le `Service` de type `NodePort` par `ClusterIP` dans `grafana.yaml`, puis ajouter :

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
    - host: grafana.mondomaine.com    # Remplacer par votre domaine
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
        - grafana.mondomaine.com
```

Créer un enregistrement DNS `A` pour `grafana.mondomaine.com` pointant vers l'IP publique du Hub.

---

## Troubleshooting

| Symptôme                          | Cause probable              | Solution                                                                                |
| --------------------------------- | --------------------------- | --------------------------------------------------------------------------------------- |
| Pod Prometheus `Pending`          | PVC non provisionné         | Vérifier le PVC et Longhorn sur le Spoke; voir [`longhorn.md`](../longhorn/longhorn.md) |
| `Save & test` échoue dans Grafana | Réseau Hub→Spoke bloqué     | Vérifier le pare-feu Lightsail du Spoke (port 32090) et la connectivité privée          |
| `Save & test` échoue — timeout    | Mauvaise IP ou mauvais port | Vérifier avec `curl http://<IP-Spoke>:32090/-/healthy` depuis le Hub                    |
| Pod Grafana `OOMKilled`           | Mémoire insuffisante        | Augmenter les limits dans le Deployment                                                 |
| Dashboards vides                  | Prometheus pas encore prêt  | Attendre 2 min, vérifier `/targets`                                                     |
| NodePort 32090 refusé             | Port Lightsail fermé        | **Console Lightsail → Networking → Add rule TCP 32090**                                 |

### Commande de diagnostic rapide

```bash
# Depuis le Hub — tester la connexion à Prometheus sur le Spoke
curl -s http://<IP-privée-Spoke>:32090/-/healthy
# Réponse attendue : Prometheus Server is Healthy.

# Vérifier les pods sur le Spoke
kubectl get pods -n monitoring   # (contexte Spoke)

# Vérifier les pods sur le Hub
kubectl get pods -n monitoring   # (contexte Hub)
```

---

## Résultat

```
[Hub]                          [Spoke]
Grafana :32000  ──────────→  Prometheus :32090
(accès utilisateur)            (métriques K8s)
```

Grafana sur le Hub affiche les métriques collectées par Prometheus sur le Spoke. Le seul flux réseau nécessaire est **Hub → Spoke:32090**.

