# santu/pulse-worker

Worker Python de **Pulse** : lit la file Redis `votes` et écrit chaque vote dans Postgres.

## Rôle

- `BRPOP` sur la file `votes`
- `INSERT` d’une ligne par vote (outil DevOps)
- Reconnexion automatique à Redis / Postgres

Aucun port exposé — process interne.

## Variables d’environnement

| Variable       | Défaut                                        | Description        |
| -------------- | --------------------------------------------- | ------------------ |
| `REDIS_HOST`   | `localhost`                                   | Hôte Redis         |
| `REDIS_PORT`   | `6379`                                        | Port Redis         |
| `DATABASE_URL` | `postgres://pulse:pulse@localhost:5432/pulse` | Connexion Postgres |

## Build

```bash
docker build -t santu/pulse-worker .
```

## Run

```bash
docker run -d --name pulse-worker --network pulse-net \
  -e REDIS_HOST=pulse-redis \
  -e DATABASE_URL=postgres://pulse:pulse@pulse-db:5432/pulse \
  santu/pulse-worker
```

## Logs

```bash
docker logs -f pulse-worker
```
