# santu/pulse-result

Frontend React + TypeScript d’**affichage** des résultats Pulse (lecture seule).

## Rôle

- Liste les outils DevOps avec le nombre total de votes publics
- Polling `GET /results` toutes les 2 secondes (via `/api/results`)
- Aucun formulaire de vote
- Appels API via le chemin relatif **`/api`** — nginx proxy vers le Service DNS **`api:3000`**

Pas d’URL externe : le navigateur reste sur le host du frontend ; la com. vers l’API est **interne** (réseau Docker / cluster).

## Variables de build

| Variable       | Défaut | Description                          |
| -------------- | ------ | ------------------------------------ |
| `VITE_API_URL` | `/api` | Préfixe API (proxy nginx → `api:3000`) |

## Build

```bash
docker build -t santu/pulse-result .
```

## Run

Le hostname **`api`** doit résoudre sur le même réseau :

```bash
docker run -d --name result --network pulse-net -p 8081:80 santu/pulse-result
```

Ouvre http://localhost:8081

## Dev local

```bash
npm install
npm run dev
```

Vite proxy `/api` → `http://localhost:3000` (API lancée à part).
