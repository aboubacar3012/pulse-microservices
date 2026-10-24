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

### Pourquoi ClusterIP sur Kubernetes

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

## Tests

```bash
npm ci
npm test
npm run test:coverage
```

Jest + SuperTest, Redis/Postgres mockés (pas besoin de services locaux).

Rapports générés dans `coverage/` :

| Fichier                  | Usage                                             |
| ------------------------ | ------------------------------------------------- |
| `index.html`             | Rapport HTML (navigateur / Jenkins `publishHTML`) |
| `lcov.info`              | LCOV                                              |
| `cobertura-coverage.xml` | Cobertura (Jenkins)                               |
| `junit.xml`              | Résultats de tests (Jenkins `junit`)              |

## SonarQube (SAST)

Analyse statique via le scanner npm **`@sonar/scan`**. Config projet : [`sonar-project.properties`](./sonar-project.properties).

| Propriété | Valeur |
| --------- | ------ |
| `sonar.projectKey` | `Pulse-Microservices` |
| `sonar.sources` | `src` |
| `sonar.tests` | `tests` |
| `sonar.javascript.lcov.reportPaths` | `coverage/lcov.info` |

### En local

1. Générer la couverture (LCOV lu par Sonar) :
```bash
npm ci
npm run test:coverage
```

2. Lancer le scan (token **jamais** commités — variable d’env ou credential) :
```bash
export SONAR_TOKEN=...          # token généré dans SonarQube
export SONAR_HOST_URL=http://<host>:9000

npx sonar \
  -Dsonar.host.url="$SONAR_HOST_URL" \
  -Dsonar.token="$SONAR_TOKEN" \
  -Dsonar.projectKey=Pulse-Microservices
```

Équivalent npm : `npm run test:sonar` (lit aussi `sonar-project.properties` ; il faut quand même fournir host + token).

### Dans Jenkins

Stage `SonarQube` du [`jenkinsfile`](./jenkinsfile) :

1. `npm ci` + `npm run test:coverage` → produit `coverage/lcov.info`
2. `withCredentials` (`sonar-token`) + `npx sonar` avec `sonar.host.url`, `sonar.token`, `sonar.projectKey`

Le secret est stocké dans Jenkins (**Credentials** → `sonar-token`), pas dans le dépôt.

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
