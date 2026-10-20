# santu/pulse-api

API REST de **Pulse** : accepte les votes publics et expose les résultats agrégés.

## Rôle

- `POST /vote` — `{ tool, sessionId, action: "add"|"remove" }`
- `GET /session/:sessionId` — compteurs locaux du navigateur
- `GET /results` — totaux globaux (`count` + `voters`) par outil
- `GET /tools` — liste des outils DevOps autorisés
- `GET /health` — santé du service

## Variables d’environnement

| Variable | Défaut | Description |
|----------|--------|-------------|
| `PORT` | `3000` | Port HTTP |
| `REDIS_HOST` | `localhost` | Hôte Redis |
| `REDIS_PORT` | `6379` | Port Redis |
| `DATABASE_URL` | `postgres://pulse:pulse@localhost:5432/pulse` | Connexion Postgres |
| `SESSION_TTL_SEC` | `604800` | Durée de vie session Redis (7 j) |

## Build

```bash
docker build -t santu/pulse-api .
```

## Run

```bash
docker run -d --name pulse-api --network pulse-net -p 3000:3000 \
  -e REDIS_HOST=pulse-redis \
  -e DATABASE_URL=postgres://pulse:pulse@pulse-db:5432/pulse \
  santu/pulse-api
```

## Exemples

```bash
SID=$(uuidgen | tr '[:upper:]' '[:lower:]')

curl -X POST http://localhost:3000/vote \
  -H 'Content-Type: application/json' \
  -d "{\"tool\":\"jenkins\",\"sessionId\":\"$SID\"}"

curl http://localhost:3000/session/$SID
curl http://localhost:3000/results
```
