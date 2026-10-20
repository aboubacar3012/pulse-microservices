#!/usr/bin/env python3
"""santu-pulse-worker — consomme la file Redis et persiste les votes dans Postgres."""

from __future__ import annotations

import json
import os
import time

import psycopg2
import redis

TOOLS = frozenset(
    {
        "docker",
        "ansible",
        "kubernetes",
        "linux",
        "git",
        "terraform",
        "jenkins",
        "aws",
    }
)

REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
DATABASE_URL = os.getenv(
    "DATABASE_URL", "postgres://pulse:pulse@localhost:5432/pulse"
)
VOTES_QUEUE = "votes"


def connect_redis() -> redis.Redis:
    while True:
        try:
            client = redis.Redis(
                host=REDIS_HOST,
                port=REDIS_PORT,
                decode_responses=True,
            )
            client.ping()
            print(f"redis connecté ({REDIS_HOST}:{REDIS_PORT})", flush=True)
            return client
        except Exception as exc:  # noqa: BLE001
            print(f"attente redis: {exc}", flush=True)
            time.sleep(2)


def connect_db():
    while True:
        try:
            conn = psycopg2.connect(DATABASE_URL)
            conn.autocommit = True
            print("postgres connecté", flush=True)
            return conn
        except Exception as exc:  # noqa: BLE001
            print(f"attente postgres: {exc}", flush=True)
            time.sleep(2)


def ensure_schema(conn) -> None:
    with conn.cursor() as cur:
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS votes (
              id BIGSERIAL PRIMARY KEY,
              tool TEXT NOT NULL,
              created_at TIMESTAMPTZ DEFAULT NOW()
            )
            """
        )
        cur.execute(
            "ALTER TABLE votes ADD COLUMN IF NOT EXISTS session_id TEXT"
        )
        cur.execute(
            "CREATE INDEX IF NOT EXISTS idx_votes_tool ON votes (tool)"
        )
        cur.execute(
            "CREATE INDEX IF NOT EXISTS idx_votes_session ON votes (session_id)"
        )


def apply_vote(conn, tool: str, session_id: str | None, action: str) -> None:
    with conn.cursor() as cur:
        if action == "remove":
            if session_id:
                cur.execute(
                    """
                    DELETE FROM votes
                    WHERE id = (
                      SELECT id FROM votes
                      WHERE tool = %s AND session_id = %s
                      ORDER BY id DESC
                      LIMIT 1
                    )
                    """,
                    (tool, session_id),
                )
            else:
                cur.execute(
                    """
                    DELETE FROM votes
                    WHERE id = (
                      SELECT id FROM votes
                      WHERE tool = %s
                      ORDER BY id DESC
                      LIMIT 1
                    )
                    """,
                    (tool,),
                )
            print(f"vote retiré: {tool}", flush=True)
            return

        cur.execute(
            "INSERT INTO votes (tool, session_id) VALUES (%s, %s)",
            (tool, session_id),
        )
        print(f"vote enregistré: {tool}", flush=True)


def main() -> None:
    r = connect_redis()
    conn = connect_db()
    ensure_schema(conn)
    print("santu-pulse-worker prêt", flush=True)

    while True:
        try:
            item = r.brpop(VOTES_QUEUE, timeout=5)
            if not item:
                continue

            _, payload = item
            data = json.loads(payload)
            tool = str(data.get("tool", "")).strip().lower()
            session_id = data.get("sessionId") or data.get("session_id")
            session_id = (
                str(session_id).strip().lower() if session_id else None
            )
            action = str(data.get("action", "add")).strip().lower()
            if action not in {"add", "remove"}:
                action = "add"

            if tool not in TOOLS:
                print(f"outil ignoré: {tool!r}", flush=True)
                continue

            apply_vote(conn, tool, session_id, action)
        except redis.RedisError as exc:
            print(f"erreur redis: {exc}", flush=True)
            time.sleep(2)
            r = connect_redis()
        except psycopg2.Error as exc:
            print(f"erreur postgres: {exc}", flush=True)
            time.sleep(2)
            conn = connect_db()
            ensure_schema(conn)
        except Exception as exc:  # noqa: BLE001
            print(f"erreur inattendue: {exc}", flush=True)
            time.sleep(1)


if __name__ == "__main__":
    main()
