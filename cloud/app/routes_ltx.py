from __future__ import annotations

import base64
import json
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from .comfy_runner import run_ltx_job
from .db import LtxJob, User, get_session
from .security import get_current_user

router = APIRouter(tags=["ltx"])


class CreateJobBody(BaseModel):
    prompt: str = Field(min_length=8, max_length=4000)
    duration_sec: int = Field(default=4, ge=3, le=8)
    fps: int = Field(default=24, ge=8, le=30)


class JobOut(BaseModel):
    id: str
    status: str
    prompt: str
    duration_sec: int
    error: str | None = None
    frame_w: int = 96
    frame_h: int = 52
    frame_count: int = 0
    frames_b64: list[str] | None = None
    video_url: str | None = None


def _job_to_out(job: LtxJob, *, include_frames: bool = False) -> JobOut:
    frames = None
    if include_frames and job.frames_json and job.status == "succeeded":
        frames = json.loads(job.frames_json)
    video_url = None
    if job.status == "succeeded" and job.video_path:
        video_url = f"/v1/ltx/jobs/{job.id}/video"
    return JobOut(
        id=job.id,
        status=job.status,
        prompt=job.prompt,
        duration_sec=job.duration_sec,
        error=job.error,
        frame_w=job.frame_w,
        frame_h=job.frame_h,
        frame_count=job.frame_count,
        frames_b64=frames,
        video_url=video_url,
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

        result = run_ltx_job(job.prompt, duration_sec=job.duration_sec)
        frames_b64 = [base64.b64encode(f).decode("ascii") for f in result["frames"]]
        job.status = "succeeded"
        job.comfy_prompt_id = str(result.get("comfy_job_id") or "")
        job.video_path = result["video_path"]
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


@router.post("/ltx/jobs", response_model=JobOut)
def create_job(
    body: CreateJobBody,
    background: BackgroundTasks,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_session),
):
    job = LtxJob(
        id=str(uuid.uuid4()),
        user_id=user.id,
        prompt=body.prompt.strip(),
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
):
    rows = db.scalars(
        select(LtxJob).where(LtxJob.user_id == user.id).order_by(LtxJob.created_at.desc()).limit(30)
    ).all()
    return [_job_to_out(j) for j in rows]
