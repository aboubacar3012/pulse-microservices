# Grafana et Prometheus — installation tout-en-un

Installe Grafana et Prometheus dans le même cluster avec Helm.

---

## Prérequis

Un cluster Kubernetes fonctionnel, Helm et `kubectl` configuré pour ce cluster.

### Ressources

Prévoir au moins 2 Go de RAM pour un lab allégé. Pour le stockage, installer Longhorn en suivant [`longhorn.md`](../longhorn/longhorn.md).

```bash
kubectl get storageclass
```

Le StorageClass `longhorn` doit apparaître dans la liste.

---

## 1. Ajouter le dépôt Helm

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

---

## 2. Préparer le fichier de valeurs (lab allégé)

> Pour une instance Lightsail 2 GB, utiliser ce fichier pour réduire les ressources. Sur 4 GB+, cette étape est optionnelle.

Créer le fichier `lab-values.yaml` :

```yaml
# lab-values.yaml — version allégée pour Lightsail 2 GB
prometheus:
  prometheusSpec:
    retention: 3d                    # Limiter la rétention pour économiser le disque
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

grafana:
  resources:
    requests:
      memory: "100Mi"
      cpu: "100m"
    limits:
      memory: "200Mi"
      cpu: "200m"

alertmanager:
  alertmanagerSpec:
    resources:
      requests:
        memory: "50Mi"
        cpu: "50m"
      limits:
        memory: "100Mi"
        cpu: "100m"

nodeExporter:
  resources:
    requests:
      memory: "30Mi"
      cpu: "30m"

kubeStateMetrics:
  resources:
    requests:
      memory: "50Mi"
      cpu: "50m"
```

---

## 3. Installer la stack

**Sans fichier de valeurs (instance 4 GB+) :**

```bash
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace
```

**Avec le fichier de valeurs allégé (instance 2 GB) :**

```bash
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values lab-values.yaml
```

```bash
kubectl get pods,svc -n monitoring
```

Si un pod reste en `Pending` :

```bash
# Identifier le problème
kubectl describe pod -n monitoring <nom-du-pod>
kubectl get pvc -n monitoring
kubectl describe pvc -n monitoring <nom-du-pvc>
```

---

## 4. Accéder à Grafana — NodePort (défaut)

### Déclarer les NodePorts dans le fichier de valeurs

Ajouter les entrées suivantes dans `lab-values.yaml` (ou les fusionner si le fichier existe déjà) :

```yaml
grafana:
  service:
    type: NodePort
    nodePort: 32000        # Port accessible depuis l'extérieur (30000-32767)

prometheus:
  service:
    type: NodePort
    nodePort: 32090
```

Réappliquer le chart après modification :

```bash
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values lab-values.yaml
```

Ouvrir les ports dans le pare-feu Lightsail : **Console → Instance → Networking → Add rule → TCP**.

| Service | Port |
|---|---:|
| Grafana | 32000 |
| Prometheus | 32090 |

### Accéder aux interfaces

```
Grafana    → http://<IP-publique-lightsail>:32000
Prometheus → http://<IP-publique-lightsail>:32090
```

### Récupérer le mot de passe admin Grafana

```bash
kubectl get secret -n monitoring monitoring-grafana \
  -o jsonpath='{.data.admin-password}' | base64 --decode
printf '\n'
```

> Changer le mot de passe après la première connexion : **Profile → Change password**.

---

## 5. Vérifier Prometheus et la source de données

Dans Grafana, ouvrir **Connections > Data sources** et vérifier que la source Prometheus est connectée.

Ouvrir l'interface Prometheus : <http://\<IP-publique-lightsail\>:32090>

Dans **Status > Targets**, vérifier que les cibles attendues sont `UP`.

---

## Accès Grafana via Ingress (optionnel)

Installer d'abord Traefik en suivant [`metalb-traefik.md`](../metalb-traefik.md), puis remplacer `grafana.mondomaine.com` par votre domaine.

Ajouter dans `lab-values.yaml` :

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
      - grafana.mondomaine.com
    tls:
      - hosts:
          - grafana.mondomaine.com
```

Réappliquer avec `helm upgrade` après modification.

---

## 6. Explorer les dashboards

Dans Grafana, ouvrir **Dashboards** :

- **Kubernetes / Compute Resources / Cluster** — vue d'ensemble CPU/RAM
- **Kubernetes / Nodes** — détail par nœud
- **Kubernetes / Pods** — détail par pod

Si les tableaux sont vides après quelques minutes, vérifier :

```bash
# Pods Prometheus prêts ?
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus

```

---

## 7. Mise à jour et désinstallation

Mettre à jour la release après avoir actualisé les métadonnées Helm :

```bash
helm repo update
helm upgrade monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values lab-values.yaml   # Remettre le fichier de valeurs si utilisé
```

Supprimer les ressources Helm :

```bash
helm uninstall monitoring --namespace monitoring
```

> ⚠️ La suppression de la release **ne supprime pas** les PersistentVolumes et PersistentVolumeClaims contenant les données Prometheus. Vérifier et supprimer manuellement si besoin :
>
> ```bash
> kubectl get pvc -n monitoring
> kubectl delete pvc -n monitoring --all   # À faire uniquement si vous voulez tout effacer
> ```

---

## Troubleshooting rapide

| Symptôme | Cause probable | Solution |
|----------|---------------|----------|
| Pod `Pending` indéfiniment | PVC non provisionné | Vérifier le PVC et le StorageClass Longhorn; voir [`longhorn.md`](../longhorn/longhorn.md) |
| Pod `OOMKilled` | Instance trop petite | Utiliser le `lab-values.yaml` ou upgrader l'instance |
| Grafana/Prometheus inaccessible | Port Lightsail fermé | Ouvrir le NodePort dans Console Lightsail → Networking |
| Dashboards vides | Prometheus pas encore prêt | Attendre 2 min et vérifier `/targets` |
| `Error: INSTALLATION FAILED: cannot re-use a name` | Release déjà installée | Remplacer `install` par `upgrade` ou utiliser `helm uninstall` d'abord |

---

## Documentation officielle

- [Chart kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [Valeurs par défaut du chart](https://github.com/prometheus-community/helm-charts/blob/main/charts/kube-prometheus-stack/values.yaml) — `grafana.enabled` vaut `true` par défaut.
- [Installation Traefik](../metalb-traefik.md)
- [Configuration Longhorn](../longhorn/longhorn.md)