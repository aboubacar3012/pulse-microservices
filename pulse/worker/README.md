# santu/pulse-worker

Worker Python de **Pulse** : lit la file Redis `votes` et écrit chaque vote dans Postgres.

## Rôle

- `BRPOP` sur la file `votes`
- `INSERT` d’une ligne par vote (outil DevOps)
- Reconnexion automatique à Redis / Postgres

Aucun port exposé — process **interne** uniquement (pas de Service K8s, comme voting-app).

## Variables d’environnement updated

| Variable       | Défaut (dev local)                            | En cluster / Compose |
| -------------- | --------------------------------------------- | -------------------- |
| `REDIS_HOST`   | `localhost`                                   | `redis`              |
| `REDIS_PORT`   | `6379`                                        | `6379`               |
| `DATABASE_URL` | `postgres://pulse:pulse@localhost:5432/pulse` | `...@db:5432/pulse`  |

## Build

```bash
docker build -t santu/pulse-worker .
```

## Run

```bash
docker run -d --name worker --network pulse-net \
  -e REDIS_HOST=redis \
  -e DATABASE_URL=postgres://pulse:pulse@db:5432/pulse \
  santu/pulse-worker
```

## Logs

```bash
docker logs -f worker
```
