from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

import aiosqlite


SCHEMA = """
CREATE TABLE IF NOT EXISTS conversations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT NOT NULL,
    device_id TEXT,
    role TEXT NOT NULL,
    content TEXT NOT NULL,
    route TEXT
);

CREATE TABLE IF NOT EXISTS facts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT NOT NULL,
    key TEXT UNIQUE NOT NULL,
    value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS device_state (
    device_id TEXT PRIMARY KEY,
    updated_at TEXT NOT NULL,
    state TEXT,
    payload TEXT
);
"""


class Memory:
    def __init__(self, path: Path) -> None:
        self.path = path
        self._db: aiosqlite.Connection | None = None

    async def open(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._db = await aiosqlite.connect(self.path)
        await self._db.executescript(SCHEMA)
        await self._db.commit()

    async def close(self) -> None:
        if self._db is not None:
            await self._db.close()
            self._db = None

    @property
    def db(self) -> aiosqlite.Connection:
        if self._db is None:
            raise RuntimeError("Memory database is not open")
        return self._db

    async def add_turn(self, device_id: str, role: str, content: str, route: str | None = None) -> None:
        await self.db.execute(
            "INSERT INTO conversations (created_at, device_id, role, content, route) VALUES (?, ?, ?, ?, ?)",
            (datetime.now(timezone.utc).isoformat(), device_id, role, content, route),
        )
        await self.db.commit()

    async def recent(self, device_id: str, limit: int = 8) -> list[tuple[str, str]]:
        cursor = await self.db.execute(
            "SELECT role, content FROM conversations WHERE device_id = ? ORDER BY id DESC LIMIT ?",
            (device_id, limit),
        )
        rows = await cursor.fetchall()
        return list(reversed(rows))
