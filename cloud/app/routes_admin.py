from __future__ import annotations

import os
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from .db import DAILY_LTX_LIMIT, LtxJob, User, get_session
from .security import (
    create_access_token,
    get_current_admin,
    hash_password,
    verify_password,
)

router = APIRouter(tags=["admin"])


class AdminLoginBody(BaseModel):
    email: EmailStr
    password: str


class AdminTokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_id: int
    email: str
    display_name: str


class AdminUserOut(BaseModel):
    id: int
    email: str
    display_name: str
    is_active: bool
    is_admin: bool
    daily_ltx_limit: int | None
    effective_limit: int
    used_today: int
    remaining_today: int
    created_at: str | None


class AdminUsersOut(BaseModel):
    global_daily_limit: int
    users: list[AdminUserOut]


class PatchUserBody(BaseModel):
    daily_ltx_limit: int | None = Field(default=None, ge=0, le=999)
    is_active: bool | None = None
    clear_limit: bool = False


def _day_start_utc() -> datetime:
    now = datetime.now(timezone.utc)
    return datetime(now.year, now.month, now.day, tzinfo=timezone.utc)


def _iso(dt: datetime | None) -> str | None:
    if dt is None:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc).isoformat()


def _effective_limit(user: User) -> int:
    if user.daily_ltx_limit is not None:
        return int(user.daily_ltx_limit)
    return DAILY_LTX_LIMIT


def _used_today(db: Session, user_id: int) -> int:
    start = _day_start_utc()
    return int(
        db.scalar(
            select(func.count())
            .select_from(LtxJob)
            .where(LtxJob.user_id == user_id, LtxJob.created_at >= start)
        )
        or 0
    )


def _user_out(db: Session, user: User) -> AdminUserOut:
    used = _used_today(db, user.id)
    limit = _effective_limit(user)
    return AdminUserOut(
        id=user.id,
        email=user.email,
        display_name=user.display_name or "",
        is_active=bool(user.is_active),
        is_admin=bool(user.is_admin),
        daily_ltx_limit=user.daily_ltx_limit,
        effective_limit=limit,
        used_today=used,
        remaining_today=max(0, limit - used),
        created_at=_iso(user.created_at),
    )


@router.post("/admin/login", response_model=AdminTokenOut)
def admin_login(body: AdminLoginBody, db: Session = Depends(get_session)):
    email = body.email.lower().strip()
    user = db.scalar(select(User).where(User.email == email))
    if user is None or not verify_password(body.password, user.password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid email or password")
    if not user.is_active or not user.is_admin:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin access required")
    token = create_access_token(user.id, user.email)
    return AdminTokenOut(
        access_token=token,
        user_id=user.id,
        email=user.email,
        display_name=user.display_name,
    )


@router.get("/admin/me", response_model=AdminTokenOut)
def admin_me(admin: User = Depends(get_current_admin)):
    return AdminTokenOut(
        access_token="",
        user_id=admin.id,
        email=admin.email,
        display_name=admin.display_name,
    )


@router.get("/admin/users", response_model=AdminUsersOut)
def list_users(admin: User = Depends(get_current_admin), db: Session = Depends(get_session)):
    del admin
    rows = db.scalars(select(User).order_by(User.id.asc())).all()
    return AdminUsersOut(
        global_daily_limit=DAILY_LTX_LIMIT,
        users=[_user_out(db, u) for u in rows],
    )


@router.patch("/admin/users/{user_id}", response_model=AdminUserOut)
def patch_user(
    user_id: int,
    body: PatchUserBody,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_session),
):
    del admin
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="User not found")

    raw = body.model_dump(exclude_unset=True)
    if raw.get("clear_limit") or ("daily_ltx_limit" in raw and raw["daily_ltx_limit"] is None):
        user.daily_ltx_limit = None
    elif "daily_ltx_limit" in raw and raw["daily_ltx_limit"] is not None:
        user.daily_ltx_limit = int(raw["daily_ltx_limit"])

    if "is_active" in raw and raw["is_active"] is not None:
        user.is_active = bool(raw["is_active"])

    db.commit()
    db.refresh(user)
    return _user_out(db, user)


def ensure_admin_user(db: Session) -> None:
    """Bootstrap admin from ADMIN_EMAIL / ADMIN_PASSWORD env if set."""
    email = os.environ.get("ADMIN_EMAIL", "").strip().lower()
    password = os.environ.get("ADMIN_PASSWORD", "").strip()
    if not email or not password:
        return
    user = db.scalar(select(User).where(User.email == email))
    if user is None:
        user = User(
            email=email,
            password_hash=hash_password(password),
            display_name=os.environ.get("ADMIN_NAME", "Admin")[:120],
            is_admin=True,
            is_active=True,
        )
        db.add(user)
    else:
        user.is_admin = True
        user.is_active = True
        if os.environ.get("ADMIN_PASSWORD_RESET", "").strip() in ("1", "true", "yes"):
            user.password_hash = hash_password(password)
    db.commit()
