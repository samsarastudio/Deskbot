from __future__ import annotations

import base64
import json
import os
import uuid
from datetime import datetime, timezone
from pathlib import Path

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from .comfy_runner import run_ltx_job
from .db import DAILY_LTX_LIMIT, LtxJob, User, get_session
from .security import get_current_user

router = APIRouter(tags=["ltx"])


def _effective_daily_limit(user: User) -> int:
    if getattr(user, "daily_ltx_limit", None) is not None:
        return int(user.daily_ltx_limit)
    return DAILY_LTX_LIMIT


class CreateJobBody(BaseModel):
    prompt: str = Field(min_length=8, max_length=4000)
    title: str = Field(default="", max_length=160)
    duration_sec: int = Field(default=4, ge=3, le=8)
    fps: int = Field(default=24, ge=8, le=30)


class JobOut(BaseModel):
    id: str
    status: str
    prompt: str
    title: str = ""
    duration_sec: int
    error: str | None = None
    frame_w: int = 128
    frame_h: int = 68
    frame_count: int = 0
    frames_b64: list[str] | None = None
    video_url: str | None = None
    preview_url: str | None = None
    created_at: str | None = None
    finished_at: str | None = None


class QuotaOut(BaseModel):
    limit: int
    used: int
    remaining: int
    resets_at: str


def _iso(dt: datetime | None) -> str | None:
    if dt is None:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc).isoformat()


def _day_start_utc() -> datetime:
    now = datetime.now(timezone.utc)
    return datetime(now.year, now.month, now.day, tzinfo=timezone.utc)


def _quota_for_user(db: Session, user: User) -> QuotaOut:
    start = _day_start_utc()
    used = db.scalar(
        select(func.count())
        .select_from(LtxJob)
        .where(LtxJob.user_id == user.id, LtxJob.created_at >= start)
    ) or 0
    limit = _effective_daily_limit(user)
    remaining = max(0, limit - int(used))
    from datetime import timedelta

    resets_at = (start + timedelta(days=1)).isoformat()
    return QuotaOut(limit=limit, used=int(used), remaining=remaining, resets_at=resets_at)


def _job_to_out(job: LtxJob, *, include_frames: bool = False) -> JobOut:
    frames = None
    if include_frames and job.frames_json and job.status == "succeeded":
        frames = json.loads(job.frames_json)
    video_url = None
    preview_url = None
    if job.status == "succeeded":
        if job.video_path:
            video_url = f"/v1/ltx/jobs/{job.id}/video"
        if job.preview_path:
            preview_url = f"/v1/ltx/jobs/{job.id}/preview"
    return JobOut(
        id=job.id,
        status=job.status,
        prompt=job.prompt,
        title=job.title or "",
        duration_sec=job.duration_sec,
        error=job.error,
        frame_w=job.frame_w,
        frame_h=job.frame_h,
        frame_count=job.frame_count,
        frames_b64=frames,
        video_url=video_url,
        preview_url=preview_url,
        created_at=_iso(job.created_at),
        finished_at=_iso(job.finished_at),
    )


def _run_job_worker(job_id: str) -> None:
    from .db import SessionLocal

    assert SessionLocal is not None
    db = SessionLocal()
    try:
        job = db.get(LtxJob, job_id)
        if job is None:
            return
        job.status = "running"
        db.commit()

        result = run_ltx_job(job.prompt, duration_sec=job.duration_sec, job_id=job_id)
        frames_b64 = [base64.b64encode(f).decode("ascii") for f in result["frames"]]
        job.status = "succeeded"
        job.comfy_prompt_id = str(result.get("comfy_job_id") or "")
        job.video_path = result["video_path"]
        job.preview_path = result.get("preview_path")
        job.frames_json = json.dumps(frames_b64)
        job.frame_w = result["w"]
        job.frame_h = result["h"]
        job.frame_count = len(frames_b64)
        job.finished_at = datetime.now(timezone.utc)
        job.error = None
        db.commit()
    except Exception as e:  # noqa: BLE001
        job = db.get(LtxJob, job_id)
        if job:
            job.status = "failed"
            job.error = str(e)[:2000]
            job.finished_at = datetime.now(timezone.utc)
            db.commit()
    finally:
        db.close()


@router.get("/ltx/quota", response_model=QuotaOut)
def get_quota(user: User = Depends(get_current_user), db: Session = Depends(get_session)):
    return _quota_for_user(db, user)


@router.post("/ltx/jobs", response_model=JobOut)
def create_job(
    body: CreateJobBody,
    background: BackgroundTasks,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_session),
):
    quota = _quota_for_user(db, user)
    if quota.remaining <= 0:
        raise HTTPException(
            status_code=429,
            detail=f"Daily limit reached ({quota.limit}/day). Resets at {quota.resets_at}.",
        )

    title = (body.title or "").strip()
    if not title:
        title = body.prompt.strip().split(",")[0][:80]

    job = LtxJob(
        id=str(uuid.uuid4()),
        user_id=user.id,
        prompt=body.prompt.strip(),
        title=title[:160],
        duration_sec=body.duration_sec,
        status="queued",
    )
    db.add(job)
    db.commit()
    db.refresh(job)
    background.add_task(_run_job_worker, job.id)
    return _job_to_out(job)


@router.get("/ltx/jobs/{job_id}", response_model=JobOut)
def get_job(
    job_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_session),
):
    job = db.get(LtxJob, job_id)
    if job is None or job.user_id != user.id:
        raise HTTPException(status_code=404, detail="Job not found")
    return _job_to_out(job, include_frames=job.status == "succeeded")


@router.get("/ltx/jobs", response_model=list[JobOut])
def list_jobs(
    user: User = Depends(get_current_user),
    db: Session = Depends(get_session),
    status: str | None = None,
    limit: int = 30,
):
    q = select(LtxJob).where(LtxJob.user_id == user.id)
    if status:
        q = q.where(LtxJob.status == status)
    q = q.order_by(LtxJob.created_at.desc()).limit(min(max(limit, 1), 100))
    rows = db.scalars(q).all()
    return [_job_to_out(j) for j in rows]


@router.get("/ltx/jobs/{job_id}/preview")
def get_preview(
    job_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_session),
):
    job = db.get(LtxJob, job_id)
    if job is None or job.user_id != user.id:
        raise HTTPException(status_code=404, detail="Job not found")
    path = job.preview_path
    if not path or not Path(path).is_file():
        raise HTTPException(status_code=404, detail="Preview not ready")
    return FileResponse(path, media_type="image/png", filename=f"{job_id}_preview.png")


@router.get("/ltx/jobs/{job_id}/video")
def get_video(
    job_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_session),
):
    job = db.get(LtxJob, job_id)
    if job is None or job.user_id != user.id:
        raise HTTPException(status_code=404, detail="Job not found")
    path = job.video_path
    if not path or not Path(path).is_file():
        raise HTTPException(status_code=404, detail="Video not ready")
    return FileResponse(path, media_type="video/mp4", filename=f"{job_id}.mp4")
