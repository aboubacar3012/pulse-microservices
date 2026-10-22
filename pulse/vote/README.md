# santu/pulse-vote

Frontend React + TypeScript pour **voter** sur les outils DevOps (Pulse).

## Rôle

- Affiche les 8 outils (Docker, Ansible, Kubernetes, Linux, Git, Terraform, Jenkins, AWS)
- Bouton **Voter** / **Encore +1** (votes cumulables uniquement)
- Compteurs conservés après refresh (UUID navigateur + Redis)
- Appels API via le chemin relatif **`/api`** — nginx proxy vers le Service DNS **`api:3000`**

Pas d’URL externe : le navigateur reste sur le host du frontend ; la com. vers l’API est **interne** (réseau Docker / cluster).

## `nginx.conf` — à quoi ça sert

Le runtime de l’image n’est pas Node : c’est **nginx** qui sert le build Vite (`dist/`).

| Rôle | Détail |
| ---- | ------ |
| Serveur web | Fichiers statiques + `try_files` (SPA React) + `/healthz` |
| Proxy `/api/` | Relaye vers `http://api:3000` **depuis le container** (où le DNS `api` existe) |

**Problème résolu :** le JS tourne dans le navigateur, qui ne connaît pas `api`. Sans proxy, il faudrait une URL publique vers l’API. Avec le proxy, le navigateur appelle `/api/...` sur vote ; nginx (dans Docker/K8s) parle à l’API ClusterIP.

## Variables de build updated

| Variable       | Défaut | Description                          |
| -------------- | ------ | ------------------------------------ |
| `VITE_API_URL` | `/api` | Préfixe API (proxy nginx → `api:3000`) |

## Tests

```bash
npm ci
npm test
npm run test:coverage
```

Vitest + Testing Library (jsdom). Couverture via `@vitest/coverage-v8`.

Rapport : terminal + `coverage/lcov.info` + `coverage/index.html`.

## Build

```bash
docker build -t santu/pulse-vote .
```

## Run

Le hostname **`api`** doit résoudre sur le même réseau :

```bash
docker run -d --name vote --network pulse-net -p 8080:80 santu/pulse-vote
```

Ouvre http://localhost:8080

## Dev local

```bash
npm install
npm run dev
```

Vite proxy `/api` → `http://localhost:3000` (API lancée à part).
