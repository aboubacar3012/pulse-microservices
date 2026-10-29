# Grafana et Prometheus sur un seul cluster

Installation de `kube-prometheus-stack` avec Helm. Grafana est activé par défaut : ne pas ajouter `grafana.enabled=false`.

## 1. Prérequis

- Cluster Kubernetes, `kubectl` et Helm configurés.
- Longhorn installé : [guide Longhorn](../longhorn/longhorn.md).
- StorageClass `longhorn` disponible :

```bash
kubectl get storageclass
```

## 2. Ajouter le dépôt Helm

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

## 3. Installer Grafana et Prometheus

Pour un lab avec peu de mémoire, créer `lab-values.yaml` :

```yaml
prometheus:
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

grafana:
  resources:
    requests:
      memory: 100Mi
      cpu: 100m
    limits:
      memory: 200Mi
      cpu: 200m

alertmanager:
  alertmanagerSpec:
    resources:
      requests:
        memory: 50Mi
        cpu: 50m
      limits:
        memory: 100Mi
        cpu: 100m

nodeExporter:
  resources:
    requests:
      memory: 30Mi
      cpu: 30m

kubeStateMetrics:
  resources:
    requests:
      memory: 50Mi
      cpu: 50m
```

Installer la stack. Ajouter `--values lab-values.yaml` si vous avez créé le fichier :

```bash
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values lab-values.yaml
```

Sans fichier de valeurs, exécuter la même commande sans `--values lab-values.yaml`.

Vérifier :

```bash
kubectl get pods,pvc -n monitoring
```

## 4. Accéder à Grafana avec un NodePort

Pour activer les NodePort, créer `lab-values.yaml` avec ces valeurs. Si le fichier existe déjà, fusionner les sections `prometheus` et `grafana` sans créer de clés racine en double :

```yaml
prometheus:
  service:
    type: NodePort
    nodePort: 32090

grafana:
  service:
    type: NodePort
    nodePort: 32000
```

Réappliquer le chart avec `helm upgrade --install` et le fichier de valeurs.

Autoriser TCP/32000 et TCP/32090 dans le pare-feu. Restreindre l'accès à Prometheus (32090) aux IP autorisées, car il n'a pas d'authentification par défaut. Ouvrir :

```text
Grafana    : http://<IP-DU-NOEUD>:32000
Prometheus : http://<IP-DU-NOEUD>:32090
```

Récupérer le mot de passe admin :

```bash
kubectl get secret monitoring-grafana -n monitoring \
  -o jsonpath='{.data.admin-password}' | base64 --decode; echo
```

Se connecter avec `admin`, puis changer le mot de passe.

## Option — Accéder avec un Ingress Traefik

Traefik doit déjà être installé avec un résolveur TLS configuré. Voir le [guide Traefik](../metalb-traefik.md).

Dans `lab-values.yaml`, utiliser ces valeurs Grafana (elles remplacent la configuration NodePort) :

```yaml
grafana:
  service:
    type: ClusterIP
  ingress:
    enabled: true
    ingressClassName: traefik
    annotations:
      traefik.ingress.kubernetes.io/router.entrypoints: websecure
      traefik.ingress.kubernetes.io/router.tls.certresolver: le-resolver
    hosts:
      - grafana.example.com
    tls:
      - hosts:
          - grafana.example.com
```

Créer un enregistrement DNS `A` pour `grafana.example.com` vers l'adresse publique du cluster, puis appliquer :

```bash
helm upgrade monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values lab-values.yaml
```

Ouvrir `https://grafana.example.com`.

## Vérifier Prometheus

Dans Grafana, ouvrir **Connections → Data sources** et vérifier la source Prometheus. Pour les cibles, ouvrir **Status → Targets** dans Prometheus.

Commandes utiles :

```bash
kubectl get pods,pvc -n monitoring
kubectl get svc -n monitoring
```
