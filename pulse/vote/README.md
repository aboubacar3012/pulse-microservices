# santu/pulse-vote

Frontend React + TypeScript pour **voter** sur les outils DevOps (Pulse).

## Rôle

- Affiche les 8 outils (Docker, Ansible, Kubernetes, Linux, Git, Terraform, Jenkins, AWS)
- Bouton **Voter** / **Encore +1** (votes cumulables uniquement)
- Compteurs conservés après refresh (UUID navigateur + Redis)

## Variables de build

| Variable       | Défaut                  | Description                            |
| -------------- | ----------------------- | -------------------------------------- |
| `VITE_API_URL` | `http://localhost:3000` | URL de l’API Pulse (injectée au build) |

## Build

```bash
docker build -t santu/pulse-vote .
```

## Run

```bash
docker run -d --name pulse-vote -p 8080:80 santu/pulse-vote
```

Ouvre http://localhost:8080

## Dev local

```bash
npm install
VITE_API_URL=http://localhost:3000 npm run dev
```
