#!/usr/bin/env python3
"""santu-pulse-worker — consomme la file Redis et persiste les votes dans Postgres."""

from __future__ import annotations

import json
import os
import time
from typing import Any

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


def normalize_session_id(raw: Any) -> str | None:
    if raw is None:
        return None
    value = str(raw).strip().lower()
    return value or None


def parse_vote_payload(payload: str) -> tuple[str, str | None] | None:
    """Parse un message Redis. Retourne (tool, session_id) ou None si invalide."""
    try:
        data = json.loads(payload)
    except (TypeError, json.JSONDecodeError):
        return None

    if not isinstance(data, dict):
        return None

    tool = str(data.get("tool", "")).strip().lower()
    if tool not in TOOLS:
        return None

    session_id = normalize_session_id(
        data.get("sessionId") or data.get("session_id")
    )
    return tool, session_id


def persist_vote(conn, tool: str, session_id: str | None) -> None:
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO votes (tool, session_id) VALUES (%s, %s)",
            (tool, session_id),
        )


def process_queue_item(conn, payload: str) -> bool:
    """Traite un payload. True si un vote a été persisté."""
    parsed = parse_vote_payload(payload)
    if parsed is None:
        tool_preview = ""
        try:
            tool_preview = str(json.loads(payload).get("tool", ""))
        except Exception:  # noqa: BLE001
            tool_preview = repr(payload)[:80]
        print(f"outil ignoré: {tool_preview!r}", flush=True)
        return False

    tool, session_id = parsed
    persist_vote(conn, tool, session_id)
    print(f"vote enregistré: {tool}", flush=True)
    return True


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
            process_queue_item(conn, payload)
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
