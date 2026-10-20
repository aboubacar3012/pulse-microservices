# Santu Pulse — architecture microservices

**Pulse** est une application de votes publics sur des outils DevOps.  
Organisation : **Santu**. Lab pédagogique (Docker / plus tard Kubernetes).

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

Chaque microservice applicatif a son **Dockerfile** et son **README**.  
Redis et Postgres n’ont **pas** de Dockerfile custom.

## Prérequis

- Docker + Docker Compose
- Ports libres : `3000` (API), `8080` (vote), `8081` (résultats)

## Démarrage rapide (docker compose)

Comme voting-app : un seul fichier dans `pulse/`.

```bash
cd microservices/pulse
docker compose up --build
```

| URL                   | Service   |
| --------------------- | --------- |
| http://localhost:8080 | Vote      |
| http://localhost:8081 | Résultats |
| http://localhost:3000 | API       |

Arrêt :

```bash
docker compose down
# + volume Postgres : docker compose down -v
```

Le fichier : [`pulse/docker-compose.yml`](pulse/docker-compose.yml).

## Mise en place manuelle (sans compose)

Utile pour comprendre le réseau Docker service par service.  
Depuis la racine `microservices/`.

### 1. Réseau Docker

```bash
docker network create pulse-net
```

### 2. Redis (image officielle)

```bash
docker run -d \
  --name pulse-redis \
  --network pulse-net \
  redis:7-alpine
```

### 3. Postgres (image officielle, config basique)

```bash
docker run -d \
  --name pulse-db \
  --network pulse-net \
  -e POSTGRES_USER=pulse \
  -e POSTGRES_PASSWORD=pulse \
  -e POSTGRES_DB=pulse \
  postgres:16-alpine
```

La table `votes` est créée automatiquement au démarrage de l’API ou du worker.

### 4. API

```bash
docker build -t santu/pulse-api ./pulse/api

docker run -d \
  --name pulse-api \
  --network pulse-net \
  -p 3000:3000 \
  -e REDIS_HOST=pulse-redis \
  -e DATABASE_URL=postgres://pulse:pulse@pulse-db:5432/pulse \
  santu/pulse-api
```

Vérification :

```bash
curl http://localhost:3000/health
curl http://localhost:3000/tools
```

### 5. Worker

```bash
docker build -t santu/pulse-worker ./pulse/worker

docker run -d \
  --name pulse-worker \
  --network pulse-net \
  -e REDIS_HOST=pulse-redis \
  -e DATABASE_URL=postgres://pulse:pulse@pulse-db:5432/pulse \
  santu/pulse-worker
```

```bash
docker logs -f pulse-worker
```

### 6. Frontend vote

`VITE_API_URL` est figée au **build** (URL joignable depuis le navigateur).

```bash
docker build \
  --build-arg VITE_API_URL=http://localhost:3000 \
  -t santu/pulse-vote \
  ./pulse/vote

docker run -d --name pulse-vote -p 8080:80 santu/pulse-vote
```

→ http://localhost:8080

### 7. Frontend résultats

```bash
docker build \
  --build-arg VITE_API_URL=http://localhost:3000 \
  -t santu/pulse-result \
  ./pulse/result

docker run -d --name pulse-result -p 8081:80 santu/pulse-result
```

→ http://localhost:8081

## Déployer sur Kubernetes

Le dossier [`pulse/k8s-specifications/`](pulse/k8s-specifications/) reprend le modèle de *example-voting-app* : un Deployment / Service YAML par composant.

### 1. Construire les images locales

Les frontends doivent pointer vers l’API exposée en NodePort `31002` (accessible via `localhost` sur Docker Desktop / Kind).

```bash
cd microservices/pulse

docker build -t santu/pulse-api ./api
docker build -t santu/pulse-worker ./worker
docker build --build-arg VITE_API_URL=http://localhost:31002 -t santu/pulse-vote ./vote
docker build --build-arg VITE_API_URL=http://localhost:31002 -t santu/pulse-result ./result
```

### 2. Appliquer les manifests

```bash
kubectl apply -f k8s-specifications/
```

| URL (NodePort)         | Service   |
| ---------------------- | --------- |
| http://localhost:31000 | Vote      |
| http://localhost:31001 | Résultats |
| http://localhost:31002 | API       |

### 3. Supprimer

```bash
kubectl delete -f k8s-specifications/
```

Fichiers : `db`, `redis`, `api`, `worker`, `vote`, `result` (+ services). Worker n’a pas de Service (comme voting-app).

## Tester le flux complet

```bash
# 3 votes Jenkins, 2 votes Docker
curl -s -X POST http://localhost:3000/vote -H 'Content-Type: application/json' -d '{"tool":"jenkins"}'
curl -s -X POST http://localhost:3000/vote -H 'Content-Type: application/json' -d '{"tool":"jenkins"}'
curl -s -X POST http://localhost:3000/vote -H 'Content-Type: application/json' -d '{"tool":"jenkins"}'
curl -s -X POST http://localhost:3000/vote -H 'Content-Type: application/json' -d '{"tool":"docker"}'
curl -s -X POST http://localhost:3000/vote -H 'Content-Type: application/json' -d '{"tool":"docker"}'

# Attendre ~1s que le worker traite la file
sleep 1
curl -s http://localhost:3000/results | python3 -m json.tool
```

## API (résumé)

| Méthode | Chemin     | Description                             |
| ------- | ---------- | --------------------------------------- |
| `GET`   | `/health`  | Santé                                   |
| `GET`   | `/tools`   | Liste des outils autorisés              |
| `POST`  | `/vote`    | Body `{ "tool": "aws" }` → `202`        |
| `GET`   | `/results` | Totaux `{ results: [{ tool, count }] }` |

## Arrêt / nettoyage

```bash
docker rm -f pulse-vote pulse-result pulse-api pulse-worker pulse-redis pulse-db
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

- Ingress unique devant vote + result + api
- Déploiement EKS / storage persistant (PVC) pour Postgres
- Cache Redis des totaux côté `GET /results`

## Docs par service

- [pulse/api/README.md](pulse/api/README.md)
- [pulse/worker/README.md](pulse/worker/README.md)
- [pulse/vote/README.md](pulse/vote/README.md)
- [pulse/result/README.md](pulse/result/README.md)
