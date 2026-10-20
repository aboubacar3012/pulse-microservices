# Santu Pulse — architecture microservices

**Pulse** est une application de votes publics sur des outils DevOps.  
Organisation : **Santu**. Lab pédagogique (Docker / Kubernetes).

## Idée produit

Les utilisateurs votent pour leurs outils préférés :

`docker` · `ansible` · `kubernetes` · `linux` · `git` · `terraform` · `jenkins` · `aws`

- On peut voter pour **plusieurs outils**
- On peut voter **plusieurs fois** le même outil (ex. Jenkins ×10, Docker ×30)
- **Aucun enregistrement du votant** — votes publics, totaux globaux uniquement
- Deux interfaces : une pour **voter**, une pour **voir les résultats**

## Architecture

![Architecture Pulse Vote](./Pulse_Vote_Microservices_Architecture.png)

| Service   | Image                | Rôle                                    | Code             |
| --------- | -------------------- | --------------------------------------- | ---------------- |
| Vote UI   | `santu/pulse-vote`   | Interface de vote                       | `pulse/vote/`    |
| Result UI | `santu/pulse-result` | Affichage des scores                    | `pulse/result/`  |
| API       | `santu/pulse-api`    | REST + enqueue Redis + lecture Postgres | `pulse/api/`     |
| Worker    | `santu/pulse-worker` | Consomme Redis → écrit Postgres         | `pulse/worker/`  |
| Redis     | `redis:7-alpine`     | File de votes (`votes`)                 | image officielle |
| Postgres  | `postgres:16-alpine` | Persistance des votes                   | image officielle |

### Communication interne (Docker / Kubernetes)

Toute la com. inter-services passe par les **noms DNS** (Service K8s ou service Compose) — pas d’URL externe :

| Qui → Qui        | Hostname DNS |
| ---------------- | ------------ |
| vote/result → API | `api`       |
| api / worker → Redis | `redis`  |
| api / worker → Postgres | `db`  |

```
Navigateur → vote | result (ports exposés)
                ↓  nginx /api/
             Service "api" → redis · db
             Worker        → redis · db
```

Les frontends appellent le chemin relatif `/api` ; nginx proxy vers `http://api:3000`.  
Le navigateur ne parle jamais directement à Redis, Postgres ni au worker.

Chaque microservice applicatif a son **Dockerfile** et son **README**.  
Redis et Postgres n’ont **pas** de Dockerfile custom.

## Prérequis

- Docker + Docker Compose
- Ports libres : `8080` (vote), `8081` (résultats) — `3000` optionnel (debug API)

## Démarrage rapide (docker compose)

Comme voting-app : un seul fichier dans `pulse/`.

```bash
cd microservices/pulse
docker compose up --build
```

| URL                   | Service              |
| --------------------- | -------------------- |
| http://localhost:8080 | Vote (+ proxy `/api`) |
| http://localhost:8081 | Résultats (+ proxy `/api`) |
| http://localhost:3000 | API (debug uniquement) |

Arrêt :

```bash
docker compose down
# + volume Postgres : docker compose down -v
```

Le fichier : [`pulse/docker-compose.yml`](pulse/docker-compose.yml).

## Mise en place manuelle (sans compose)

Utile pour comprendre le réseau Docker. Les **noms de containers** doivent matcher les DNS (`api`, `redis`, `db`) pour que nginx et l’API résolvent correctement.

Depuis la racine `microservices/`.

### 1. Réseau Docker

```bash
docker network create pulse-net
```

### 2. Redis

```bash
docker run -d --name redis --network pulse-net redis:7-alpine
```

### 3. Postgres

```bash
docker run -d --name db --network pulse-net \
  -e POSTGRES_USER=pulse \
  -e POSTGRES_PASSWORD=pulse \
  -e POSTGRES_DB=pulse \
  postgres:16-alpine
```

La table `votes` est créée automatiquement au démarrage de l’API ou du worker.

### 4. API

```bash
docker build -t santu/pulse-api ./pulse/api

docker run -d --name api --network pulse-net -p 3000:3000 \
  -e REDIS_HOST=redis \
  -e DATABASE_URL=postgres://pulse:pulse@db:5432/pulse \
  santu/pulse-api
```

```bash
curl http://localhost:3000/health
curl http://localhost:3000/tools
```

### 5. Worker

```bash
docker build -t santu/pulse-worker ./pulse/worker

docker run -d --name worker --network pulse-net \
  -e REDIS_HOST=redis \
  -e DATABASE_URL=postgres://pulse:pulse@db:5432/pulse \
  santu/pulse-worker
```

```bash
docker logs -f worker
```

### 6. Frontend vote / result

Build avec `VITE_API_URL=/api` (défaut Dockerfile). nginx proxy vers le hostname `api`.

```bash
docker build -t santu/pulse-vote ./pulse/vote
docker run -d --name vote --network pulse-net -p 8080:80 santu/pulse-vote

docker build -t santu/pulse-result ./pulse/result
docker run -d --name result --network pulse-net -p 8081:80 santu/pulse-result
```

→ http://localhost:8080 · http://localhost:8081

## Déployer sur Kubernetes

Le dossier [`pulse/k8s-specifications/`](pulse/k8s-specifications/) reprend le modèle de *example-voting-app* : un Deployment / Service YAML par composant.

> Les Dockerfiles forcent **`linux/amd64`** (runtime).  
> Sur Mac, les frontends compilent Vite en natif (`$BUILDPLATFORM`) puis packagent nginx amd64 — évite le crash esbuild sous QEMU.

Les Services K8s s’appellent `api`, `redis`, `db`, `vote`, `result` — mêmes noms qu’en Compose.

### 1. Build & push (Docker Hub, amd64)

Prérequis : `docker login` (ex. `aboubacar99`).

```bash
cd microservices/pulse

docker buildx build --platform linux/amd64 \
  -t aboubacar99/pulse-vote --push ./vote

docker buildx build --platform linux/amd64 \
  -t aboubacar99/pulse-result --push ./result

docker buildx build --platform linux/amd64 \
  -t aboubacar99/pulse-api --push ./api

docker buildx build --platform linux/amd64 \
  -t aboubacar99/pulse-worker --push ./worker
```

### 2. Appliquer les manifests

```bash
kubectl apply -f k8s-specifications/
kubectl rollout restart deployment/api deployment/worker deployment/vote deployment/result
```

| URL (NodePort)         | Service                 |
| ---------------------- | ----------------------- |
| http://localhost:31000 | Vote (+ proxy `/api`)   |
| http://localhost:31001 | Résultats (+ proxy `/api`) |
| http://localhost:31002 | API (debug uniquement)  |

Tester depuis le cluster (sans URL externe) :

```bash
kubectl exec -it deploy/vote -- wget -qO- http://api:3000/health
kubectl exec -it deploy/api -- nc -zv redis 6379
kubectl exec -it deploy/api -- nc -zv db 5432
```

### 3. Supprimer

```bash
kubectl delete -f k8s-specifications/
```

Fichiers : `db`, `redis`, `api`, `worker`, `vote`, `result` (+ services).  
Worker n’a pas de Service (comme voting-app).

## Tester le flux complet

Via le proxy vote (comme le navigateur) ou l’API en debug :

```bash
# Via vote (Compose) — même chemin que le frontend
curl -s -X POST http://localhost:8080/api/vote \
  -H 'Content-Type: application/json' \
  -d '{"tool":"jenkins"}'

# Ou API directe (debug)
curl -s -X POST http://localhost:3000/vote \
  -H 'Content-Type: application/json' \
  -d '{"tool":"docker"}'

sleep 1
curl -s http://localhost:8080/api/results | python3 -m json.tool
```

## API (résumé)

| Méthode | Chemin     | Description                             |
| ------- | ---------- | --------------------------------------- |
| `GET`   | `/health`  | Santé                                   |
| `GET`   | `/tools`   | Liste des outils autorisés              |
| `POST`  | `/vote`    | Body `{ "tool": "aws" }` → `202`        |
| `GET`   | `/results` | Totaux `{ results: [{ tool, count }] }` |

Côté frontend : préfixe `/api` → nginx → mêmes chemins sur `api:3000`.

## Arrêt / nettoyage

```bash
docker rm -f vote result api worker redis db
docker network rm pulse-net
```

Pour aussi supprimer les images :

```bash
docker rmi santu/pulse-vote santu/pulse-result santu/pulse-api santu/pulse-worker
```

## Structure du dépôt

```
microservices/
├── README.md                 ← ce fichier
└── pulse/
    ├── docker-compose.yml    # stack complète (style voting-app)
    ├── k8s-specifications/   # manifests K8s (style voting-app)
    ├── api/                  # Node.js + Dockerfile
    ├── worker/               # Python + Dockerfile
    ├── vote/                 # React/TS vote + Dockerfile
    └── result/               # React/TS résultats + Dockerfile
```

## Suite possible (hors scope actuel)

- Ingress unique devant vote + result
- Déploiement EKS / storage persistant (PVC) pour Postgres
- Cache Redis des totaux côté `GET /results`

## Docs par service

- [pulse/api/README.md](pulse/api/README.md)
- [pulse/worker/README.md](pulse/worker/README.md)
- [pulse/vote/README.md](pulse/vote/README.md)
- [pulse/result/README.md](pulse/result/README.md)
