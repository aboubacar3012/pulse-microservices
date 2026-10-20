# santu/pulse-result

Frontend React + TypeScript d’**affichage** des résultats Pulse (lecture seule).

## Rôle

- Liste les outils DevOps avec le nombre total de votes publics
- Polling `GET /results` toutes les 2 secondes
- Aucun formulaire de vote

## Variables de build

| Variable       | Défaut                  | Description                            |
| -------------- | ----------------------- | -------------------------------------- |
| `VITE_API_URL` | `http://localhost:3000` | URL de l’API Pulse (injectée au build) |

## Build

```bash
docker build -t santu/pulse-result .
```

## Run

```bash
docker run -d --name pulse-result -p 8081:80 santu/pulse-result
```

Ouvre http://localhost:8081

## Dev local

```bash
npm install
VITE_API_URL=http://localhost:3000 npm run dev
```
