"""Tests unitaires du worker Pulse."""

from __future__ import annotations

import json
from unittest.mock import MagicMock

import pytest

import worker


class TestNormalizeSessionId:
    def test_none(self):
        assert worker.normalize_session_id(None) is None

    def test_empty(self):
        assert worker.normalize_session_id("  ") is None

    def test_trim_and_lower(self):
        assert (
            worker.normalize_session_id("  ABC-DEF  ") == "abc-def"
        )


class TestParseVotePayload:
    def test_valid_payload(self):
        payload = json.dumps(
            {"tool": "Jenkins", "sessionId": "SID-1", "ts": 1}
        )
        assert worker.parse_vote_payload(payload) == ("jenkins", "sid-1")

    def test_session_id_snake_case(self):
        payload = json.dumps({"tool": "docker", "session_id": "ABC"})
        assert worker.parse_vote_payload(payload) == ("docker", "abc")

    def test_missing_session(self):
        payload = json.dumps({"tool": "git"})
        assert worker.parse_vote_payload(payload) == ("git", None)

    def test_unknown_tool(self):
        payload = json.dumps({"tool": "nginx", "sessionId": "x"})
        assert worker.parse_vote_payload(payload) is None

    def test_invalid_json(self):
        assert worker.parse_vote_payload("{not-json") is None

    def test_non_object(self):
        assert worker.parse_vote_payload(json.dumps(["docker"])) is None

    @pytest.mark.parametrize("tool", sorted(worker.TOOLS))
    def test_all_allowed_tools(self, tool: str):
        payload = json.dumps({"tool": tool, "sessionId": "s"})
        assert worker.parse_vote_payload(payload) == (tool, "s")


class TestPersistAndProcess:
    def test_persist_vote_inserts(self):
        conn = MagicMock()
        cur = MagicMock()
        conn.cursor.return_value.__enter__.return_value = cur

        worker.persist_vote(conn, "aws", "sess-1")

        cur.execute.assert_called_once_with(
            "INSERT INTO votes (tool, session_id) VALUES (%s, %s)",
            ("aws", "sess-1"),
        )

    def test_process_queue_item_persists_valid_vote(self):
        conn = MagicMock()
        cur = MagicMock()
        conn.cursor.return_value.__enter__.return_value = cur

        ok = worker.process_queue_item(
            conn, json.dumps({"tool": "terraform", "sessionId": "S1"})
        )

        assert ok is True
        cur.execute.assert_called_once()
        assert cur.execute.call_args.args[1] == ("terraform", "s1")

    def test_process_queue_item_skips_invalid(self):
        conn = MagicMock()
        ok = worker.process_queue_item(
            conn, json.dumps({"tool": "unknown"})
        )
        assert ok is False
        conn.cursor.assert_not_called()
