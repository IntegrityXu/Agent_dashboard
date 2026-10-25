#!/usr/bin/env python3
"""Read-only, metadata-only observations of a user-designated disposable thread.

This is a discovery tool, not a production adapter. It never reads item_json,
rollouts, credentials, task titles, or message text. Do not infer account scope
or a live event boundary from this report.
"""
import argparse
import hashlib
import json
import sqlite3
import uuid
from datetime import datetime, timezone
from pathlib import Path


def inspect(codex_directory: Path, thread_id: str) -> dict:
    uuid.UUID(thread_id)
    result = {
        "observedAt": datetime.now(timezone.utc).isoformat(),
        "testThreadDigest": hashlib.sha256(thread_id.encode()).hexdigest()[:12],
        "mode": "read-only-discovery",
    }
    queries = {
        "state_5.sqlite": {
            "receiptRows": "SELECT first_unread_turn IS NOT NULL, revision, last_published_turn IS NOT NULL FROM thread_read_receipts WHERE thread_id=?",
            "ownership": "SELECT creator_account_id IS NOT NULL, creator_user_id IS NOT NULL, archived, history_mode FROM threads WHERE id=?",
        },
        "thread_history_1.sqlite": {
            "turns": "SELECT status, started_at, completed_at FROM thread_turns WHERE thread_id=? ORDER BY rollout_ordinal",
            "itemTypes": "SELECT item_type, count(*) FROM thread_items WHERE thread_id=? GROUP BY item_type",
        },
    }
    for filename, selections in queries.items():
        with sqlite3.connect((codex_directory / filename).as_uri() + "?mode=ro", uri=True, timeout=1) as db:
            db.execute("PRAGMA query_only=ON")
            result[filename] = {key: db.execute(sql, (thread_id,)).fetchall() for key, sql in selections.items()}
    document = json.loads((codex_directory / ".codex-global-state.json").read_text())
    state = document.get("electron-thread-read-state-v1", {})
    result["desktopReadStoreVersion"] = state.get("version")
    memberships = []

    def walk(value, path=""):
        if isinstance(value, dict):
            for key, child in value.items():
                # Redact account/host identity hashes. Only print structural paths.
                component = "<identity>" if len(key) > 40 else key
                walk(child, path + "/" + component)
        elif isinstance(value, list):
            memberships.append({"path": path, "containsTest": thread_id in value})

    walk(state)
    result["desktopReadStoreMemberships"] = memberships
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("thread_id", help="User-designated disposable thread UUID")
    parser.add_argument("--codex-directory", type=Path, default=Path.home() / ".codex")
    args = parser.parse_args()
    print(json.dumps(inspect(args.codex_directory.resolve(), args.thread_id), indent=2))
