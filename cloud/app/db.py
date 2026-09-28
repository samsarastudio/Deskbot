from __future__ import annotations

import os
from datetime import datetime, timezone
from pathlib import Path

from sqlalchemy import Boolean, DateTime, Integer, String, Text, create_engine, text
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DB = f"sqlite:///{(ROOT / 'data' / 'deskbot.db').as_posix()}"

DAILY_LTX_LIMIT = int(os.environ.get("DAILY_LTX_LIMIT", "3"))


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    email: Mapped[str] = mapped_column(String(320), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    display_name: Mapped[str] = mapped_column(String(120), default="")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    is_admin: Mapped[bool] = mapped_column(Boolean, default=False)
    # None = use global DAILY_LTX_LIMIT
    daily_ltx_limit: Mapped[int | None] = mapped_column(Integer, nullable=True, default=None)


class LtxJob(Base):
    __tablename__ = "ltx_jobs"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[int] = mapped_column(Integer, index=True)
    prompt: Mapped[str] = mapped_column(Text)
    title: Mapped[str] = mapped_column(String(160), default="")
    duration_sec: Mapped[int] = mapped_column(Integer, default=4)
    status: Mapped[str] = mapped_column(String(32), default="queued")
    error: Mapped[str | None] = mapped_column(Text, nullable=True)
    comfy_prompt_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    video_path: Mapped[str | None] = mapped_column(String(512), nullable=True)
    preview_path: Mapped[str | None] = mapped_column(String(512), nullable=True)
    frames_json: Mapped[str | None] = mapped_column(Text, nullable=True)
    frame_w: Mapped[int] = mapped_column(Integer, default=128)
    frame_h: Mapped[int] = mapped_column(Integer, default=68)
    frame_count: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
    finished_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


_engine = None
SessionLocal = None


def _migrate(engine) -> None:
    """Add columns introduced after first deploy (SQLite)."""
    with engine.begin() as conn:
        job_cols = {row[1] for row in conn.execute(text("PRAGMA table_info(ltx_jobs)")).fetchall()}
        if "title" not in job_cols:
            conn.execute(text("ALTER TABLE ltx_jobs ADD COLUMN title VARCHAR(160) DEFAULT ''"))
        if "preview_path" not in job_cols:
            conn.execute(text("ALTER TABLE ltx_jobs ADD COLUMN preview_path VARCHAR(512)"))

        user_cols = {row[1] for row in conn.execute(text("PRAGMA table_info(users)")).fetchall()}
        if "is_admin" not in user_cols:
            conn.execute(text("ALTER TABLE users ADD COLUMN is_admin BOOLEAN DEFAULT 0"))
        if "daily_ltx_limit" not in user_cols:
            conn.execute(text("ALTER TABLE users ADD COLUMN daily_ltx_limit INTEGER"))


def init_db() -> None:
    global _engine, SessionLocal
    db_url = os.environ.get("DATABASE_URL", DEFAULT_DB)
    connect_args = {"check_same_thread": False} if db_url.startswith("sqlite") else {}
    if db_url.startswith("sqlite"):
        Path(db_url.replace("sqlite:///", "")).parent.mkdir(parents=True, exist_ok=True)
    _engine = create_engine(db_url, connect_args=connect_args)
    SessionLocal = sessionmaker(bind=_engine, autoflush=False, autocommit=False)
    Base.metadata.create_all(_engine)
    if db_url.startswith("sqlite"):
        _migrate(_engine)


def get_session():
    assert SessionLocal is not None
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
