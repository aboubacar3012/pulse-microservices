# santu/pulse-vote

Frontend React + TypeScript pour **voter** sur les outils DevOps (Pulse).

## Rôle

- Affiche les 8 outils (Docker, Ansible, Kubernetes, Linux, Git, Terraform, Jenkins, AWS)
- Bouton **Voter** / **Encore +1** (votes cumulables uniquement)
- Compteurs conservés après refresh (UUID navigateur + Redis)
- Appels API via le chemin relatif **`/api`** — nginx proxy vers le Service DNS **`api:3000`**

Pas d’URL externe : le navigateur reste sur le host du frontend ; la com. vers l’API est **interne** (réseau Docker / cluster).

## Variables de build

| Variable       | Défaut | Description                          |
| -------------- | ------ | ------------------------------------ |
| `VITE_API_URL` | `/api` | Préfixe API (proxy nginx → `api:3000`) |

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
