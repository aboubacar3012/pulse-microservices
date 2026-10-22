# Santu Pulse — mode d’emploi

> **Rôle de ce fichier** : produit, démarrage local, tests, API, déploiement manuel.  
> **Architecture lab** (infra hub & spoke, CI/CD, domaines, choix ClusterIP/nginx) → [`explication_de_larchitecture_du_lab.md`](./explication_de_larchitecture_du_lab.md).

**Pulse** : votes publics sur des outils DevOps. Organisation **Santu**. Lab Docker / Kubernetes.

## Idée produit

Outils votables : `docker` · `ansible` · `kubernetes` · `linux` · `git` · `terraform` · `jenkins` · `aws`

- Plusieurs outils, votes cumulables (ex. Jenkins ×10)
- Aucun enregistrement du votant — totaux globaux uniquement
- Deux UIs : **voter** et **voir les résultats**

Schéma & détail des services : [architecture du lab](./explication_de_larchitecture_du_lab.md) · [`Pulse_Vote_Microservices_Architecture.png`](./Pulse_Vote_Microservices_Architecture.png)

| Service          | Code               | Image locale (Compose)                  |
| ---------------- | ------------------ | --------------------------------------- |
| Vote UI          | `pulse/vote/`      | `santu/pulse-vote`                      |
| Result UI        | `pulse/result/`    | `santu/pulse-result`                    |
| API              | `pulse/api/`       | `santu/pulse-api`                       |
| Worker           | `pulse/worker/`    | `santu/pulse-worker`                    |
| Redis / Postgres | images officielles | `redis:7-alpine` · `postgres:16-alpine` |

DNS internes (Compose & K8s) : `api`, `redis`, `db`. Les frontends appellent `/api` ; nginx proxy vers `http://api:3000`.

## Prérequis

- Docker + Docker Compose
- Ports libres : `8080` (vote), `8081` (résultats) — `3000` optionnel (debug API)

## Démarrage rapide (docker compose)

```bash
cd microservices/pulse
docker compose up --build
```

| URL                   | Service                    |
| --------------------- | -------------------------- |
| http://localhost:8080 | Vote (+ proxy `/api`)      |
| http://localhost:8081 | Résultats (+ proxy `/api`) |
| http://localhost:3000 | API (debug uniquement)     |

```bash
docker compose down
# + volume Postgres : docker compose down -v
```

Fichier : [`pulse/docker-compose.yml`](pulse/docker-compose.yml).

## Mise en place manuelle (sans compose)

Utile pour comprendre le réseau Docker. Les **noms de containers** doivent matcher les DNS (`api`, `redis`, `db`).

Depuis la racine `microservices/` :

```bash
docker network create pulse-net

docker run -d --name redis --network pulse-net redis:7-alpine

docker run -d --name db --network pulse-net \
  -e POSTGRES_USER=pulse \
  -e POSTGRES_PASSWORD=pulse \
  -e POSTGRES_DB=pulse \
  postgres:16-alpine

docker build -t santu/pulse-api ./pulse/api
docker run -d --name api --network pulse-net -p 3000:3000 \
  -e REDIS_HOST=redis \
  -e DATABASE_URL=postgres://pulse:pulse@db:5432/pulse \
  santu/pulse-api

docker build -t santu/pulse-worker ./pulse/worker
docker run -d --name worker --network pulse-net \
  -e REDIS_HOST=redis \
  -e DATABASE_URL=postgres://pulse:pulse@db:5432/pulse \
  santu/pulse-worker

docker build -t santu/pulse-vote ./pulse/vote
docker run -d --name vote --network pulse-net -p 8080:80 santu/pulse-vote

docker build -t santu/pulse-result ./pulse/result
docker run -d --name result --network pulse-net -p 8081:80 santu/pulse-result
```

→ http://localhost:8080 · http://localhost:8081

La table `votes` est créée au démarrage de l’API ou du worker.

## Déployer sur Kubernetes (manuel)

Manifests : [`k8s-specifications/`](k8s-specifications/) (en lab, synchronisés aussi via Argo CD — voir [architecture](./explication_de_larchitecture_du_lab.md)).

> Les Dockerfiles forcent **`linux/amd64`**. Sur Mac, Vite compile en natif (`$BUILDPLATFORM`) puis nginx est packagé amd64.

### 1. Build & push (Docker Hub)

```bash
cd microservices/pulse
docker login   # ex. aboubacar99

docker buildx build --platform linux/amd64 -t aboubacar99/pulse-vote --push ./vote
docker buildx build --platform linux/amd64 -t aboubacar99/pulse-result --push ./result
docker buildx build --platform linux/amd64 -t aboubacar99/pulse-api --push ./api
docker buildx build --platform linux/amd64 -t aboubacar99/pulse-worker --push ./worker
```

### 2. Appliquer les manifests

```bash
kubectl apply -f k8s-specifications/
kubectl rollout restart deployment/api deployment/worker deployment/vote deployment/result
```

| URL (NodePort)         | Service                    |
| ---------------------- | -------------------------- |
| http://localhost:31000 | Vote (+ proxy `/api`)      |
| http://localhost:31001 | Résultats (+ proxy `/api`) |

```bash
# Depuis un pod
kubectl exec -it deploy/vote -- wget -qO- http://api:3000/health
kubectl exec -it deploy/api -- nc -zv redis 6379
kubectl exec -it deploy/api -- nc -zv db 5432

# Depuis l’extérieur (via proxy frontend)
curl -s http://localhost:31000/api/health
curl -s http://localhost:31000/api/results
```

### 3. Supprimer

```bash
kubectl delete -f k8s-specifications/
```

## Tests unitaires

```bash
# API (Jest + mocks Redis/Postgres)
cd pulse/api && npm ci && npm test

# Worker (pytest)
cd pulse/worker && pip install -r requirements-dev.txt && pytest -q

# Frontends (Vitest)
cd pulse/vote && npm ci && npm test
cd pulse/result && npm ci && npm test
```

## Tester le flux complet

```bash
SID=$(uuidgen | tr '[:upper:]' '[:lower:]')

curl -s -X POST http://localhost:8080/api/vote \
  -H 'Content-Type: application/json' \
  -d "{\"tool\":\"jenkins\",\"sessionId\":\"$SID\"}"

# Ou API directe (debug)
curl -s -X POST http://localhost:3000/vote \
  -H 'Content-Type: application/json' \
  -d "{\"tool\":\"docker\",\"sessionId\":\"$SID\"}"

sleep 1
curl -s http://localhost:8080/api/results | python3 -m json.tool
```

## API (résumé)

| Méthode | Chemin     | Description                             |
| ------- | ---------- | --------------------------------------- |
| `GET`   | `/health`  | Santé                                   |
| `GET`   | `/tools`   | Liste des outils autorisés              |
| `POST`  | `/vote`    | Body `{ "tool", "sessionId" }` → `202`  |
| `GET`   | `/results` | Totaux `{ results, totalVotes, totalVoters }` |

Côté frontend : préfixe `/api` → nginx → mêmes chemins sur `api:3000`.

## Arrêt / nettoyage

```bash
docker rm -f vote result api worker redis db
docker network rm pulse-net
docker rmi santu/pulse-vote santu/pulse-result santu/pulse-api santu/pulse-worker
```

## Docs par service

- [pulse/api/README.md](pulse/api/README.md)
- [pulse/worker/README.md](pulse/worker/README.md)
- [pulse/vote/README.md](pulse/vote/README.md)
- [pulse/result/README.md](pulse/result/README.md)

## Suite possible

- Ingress unique devant vote + result
- PVC pour Postgres / déploiement EKS
- Cache Redis des totaux côté `GET /results`
