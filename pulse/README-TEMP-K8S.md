# TEMP — Build local sur le serveur + déploiement K8s

> Fichier temporaire. À supprimer quand le flux Docker Hub / CI sera en place.

## Contexte

- Clone du repo **directement sur le serveur** (node Linux du cluster)
- Build des images **sur place** (évite le problème Mac arm64 vs node amd64)
- Les Deployments utilisent `santu/pulse-*:latest` avec `imagePullPolicy: Never` (pas de pull Docker Hub)

## 1. Build toutes les images

```bash
cd pulse

# URL de l’API vue depuis TON navigateur (NodePort api = 31002)
export VITE_API_URL="${VITE_API_URL:-http://localhost:31002}"

docker build -t santu/pulse-api:latest ./api
docker build -t santu/pulse-worker:latest ./worker
docker build -t santu/pulse-vote:latest ./vote
docker build -t santu/pulse-result:latest ./result
```

### Une seule commande (copier-coller)

```bash
cd pulse && \
VITE_API_URL="${VITE_API_URL:-http://localhost:31002}" && \
docker build -t santu/pulse-api:latest ./api && \
docker build -t santu/pulse-worker:latest ./worker && \
docker build --build-arg VITE_API_URL="$VITE_API_URL" -t santu/pulse-vote:latest ./vote && \
docker build --build-arg VITE_API_URL="$VITE_API_URL" -t santu/pulse-result:latest ./result && \
docker images 'santu/pulse-*'
```

Si l’API n’est pas sur `localhost:31002` (autre IP du serveur) :

```bash
export VITE_API_URL=http://IP_DU_SERVEUR:31002
# puis relancer le build vote + result uniquement
```

## 2. Runtime container ≠ Docker ? (containerd / k3s)

Si Kubernetes n’utilise **pas** le daemon Docker (souvent `containerd`), l’image buildée avec `docker` n’est pas visible pour les Pods. Il faut l’importer.

### containerd (kubeadm classique)

```bash
for img in santu/pulse-api santu/pulse-worker santu/pulse-vote santu/pulse-result; do
  docker save "$img:latest" | sudo ctr -n k8s.io images import -
done
```

### k3s

```bash
for img in santu/pulse-api santu/pulse-worker santu/pulse-vote santu/pulse-result; do
  docker save "$img:latest" | sudo k3s ctr images import -
done
```

## 3. Déployer

```bash
cd pulse
kubectl apply -f k8s-specifications/
kubectl get pods -w
```

## 4. Accès (NodePorts)

| App | URL |
|-----|-----|
| Vote | http://IP_SERVEUR:31000 |
| Résultats | http://IP_SERVEUR:31001 |
| API | http://IP_SERVEUR:31002 |

## 5. Après un rebuild

```bash
# rebuild images (étape 1)
kubectl rollout restart deployment/api deployment/worker deployment/vote deployment/result
# ou
kubectl delete pod -l 'app in (api,worker,vote,result)'
```

## Images utilisées par les manifests

| Deployment | Image | Pull |
|------------|-------|------|
| api | `santu/pulse-api:latest` | `Never` |
| worker | `santu/pulse-worker:latest` | `Never` |
| vote | `santu/pulse-vote:latest` | `Never` |
| result | `santu/pulse-result:latest` | `Never` |
| redis / db | images officielles | pull registry OK |

`imagePullPolicy: Never` = Kubernetes **ne télécharge pas** : l’image doit déjà exister sur le node qui schedule le Pod.

## Multi-nodes

Build (ou importe) les images sur **chaque node** susceptible de recevoir les Pods, ou force le schedule sur le node de build (`nodeSelector` / `nodeName`) — hors scope de ce TEMP.
