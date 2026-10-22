# santu/pulse-worker

Worker Python de **Pulse** : lit la file Redis `votes` et écrit chaque vote dans Postgres.

## Rôle

- `BRPOP` sur la file `votes`
- `INSERT` d’une ligne par vote (outil DevOps + `session_id`)
- Reconnexion automatique à Redis / Postgres

Aucun port exposé — process **interne** uniquement (pas de Service K8s, comme voting-app).

## Variables d’environnement

| Variable       | Défaut (dev local)                            | En cluster / Compose |
| -------------- | --------------------------------------------- | -------------------- |
| `REDIS_HOST`   | `localhost`                                   | `redis`              |
| `REDIS_PORT`   | `6379`                                        | `6379`               |
| `DATABASE_URL` | `postgres://pulse:pulse@localhost:5432/pulse` | `...@db:5432/pulse`  |

## Tests

Les tests unitaires (`test_worker.py`) importent `worker.py`, qui dépend de `psycopg2` et `redis`.  
Il faut donc un **venv** avec les deps — pas le `pytest` global du système (sinon `ModuleNotFoundError: psycopg2`).

Depuis ce dossier (`pulse/worker`) :

```bash
cd pulse/worker

python3 -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r requirements-dev.txt

pytest -q
pytest --cov=worker --cov-report=term-missing --cov-report=html --cov-report=lcov
```

Relancer plus tard (venv déjà créé) :

```bash
cd pulse/worker
source .venv/bin/activate
pytest -q
pytest --cov=worker --cov-report=term-missing --cov-report=html --cov-report=lcov
```

Depuis la racine `microservices/` :

```bash
pulse/worker/.venv/bin/pytest -q pulse/worker
pulse/worker/.venv/bin/pytest --cov=worker --cov-report=term-missing \
  --cov-report=html:pulse/worker/htmlcov \
  --cov-report=lcov:pulse/worker/coverage.lcov \
  pulse/worker
```

Rapport HTML : `htmlcov/index.html`.  
`.venv/`, `htmlcov/`, `.coverage` et `coverage/` sont ignorés par git.

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
