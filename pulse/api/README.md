# santu/pulse-api

API REST de **Pulse** : accepte les votes publics et expose les résultats agrégés.

## Rôle

- `POST /vote` — `{ tool, sessionId }`
- `GET /session/:sessionId` — compteurs locaux du navigateur
- `GET /results` — totaux globaux (`count` + `voters`) par outil
- `GET /tools` — liste des outils DevOps autorisés
- `GET /health` — santé du service

Joignable en interne sous le hostname DNS **`api`** (Service K8s / Compose).  
Les frontends n’appellent pas l’API en URL externe : nginx (vote/result) proxy `/api` → `http://api:3000`.

### Pourquoi ClusterIP sur Kubernetes updated

Le Service `api` est **ClusterIP** (pas NodePort) : pas d’exposition directe sur Internet.

- Seuls vote / result ont un NodePort (UI + proxy `/api`).
- L’API reste joignable uniquement depuis le cluster (`http://api:3000`) ou via le proxy des frontends.
- Évite de figer une URL publique (`IP:port`) dans le build des UIs.

## Variables d’environnement

| Variable          | Défaut (dev local)                            | En cluster / Compose |
| ----------------- | --------------------------------------------- | -------------------- |
| `PORT`            | `3000`                                        | `3000`               |
| `REDIS_HOST`      | `localhost`                                   | `redis`              |
| `REDIS_PORT`      | `6379`                                        | `6379`               |
| `DATABASE_URL`    | `postgres://pulse:pulse@localhost:5432/pulse` | `...@db:5432/pulse`  |
| `SESSION_TTL_SEC` | `604800`                                      | `604800` (7 j)       |

## Build

```bash
docker build -t santu/pulse-api .
```

## Run

Le container doit s’appeler (ou alias) **`api`** pour que vote/result le résolvent.

```bash
docker run -d --name api --network pulse-net -p 3000:3000 \
  -e REDIS_HOST=redis \
  -e DATABASE_URL=postgres://pulse:pulse@db:5432/pulse \
  santu/pulse-api
```

`-p 3000:3000` est optionnel (debug). En prod K8s, seul le Service ClusterIP `api` est nécessaire.

## Exemples

```bash
SID=$(uuidgen | tr '[:upper:]' '[:lower:]')

# Debug depuis l’hôte
curl -X POST http://localhost:3000/vote \
  -H 'Content-Type: application/json' \
  -d "{\"tool\":\"jenkins\",\"sessionId\":\"$SID\"}"

curl http://localhost:3000/session/$SID
curl http://localhost:3000/results

# Via le proxy frontend (comme le navigateur)
curl http://localhost:8080/api/results
```
