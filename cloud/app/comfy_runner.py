from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path

from comfy_sdk import Comfy
from comfy_sdk.exceptions import InsufficientCredits, JobFailed, Unauthorized
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW_PATH = ROOT / "workflows" / "video_ltx2_5_t2v.json"
OUT_DIR = ROOT / "data" / "jobs"

NODE_PROMPT = "405:376"
NODE_DURATION = "405:362"
NODE_FPS = "405:361"
NODE_ENHANCE = "405:383"
NODE_SAVE_VIDEO = "75"

ANIM_W = 128
ANIM_H = 68
ANIM_MAX_FRAMES = 8


def _rgb565(r: int, g: int, b: int) -> int:
    return ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3)


def encode_frame_rgb565(im: Image.Image) -> bytes:
    small = im.convert("RGB").resize((ANIM_W, ANIM_H), Image.Resampling.LANCZOS)
    out = bytearray(ANIM_W * ANIM_H * 2)
    i = 0
    for y in range(ANIM_H):
        for x in range(ANIM_W):
            r, g, b = small.getpixel((x, y))
            v = _rgb565(r, g, b)
            out[i] = v & 0xFF
            out[i + 1] = (v >> 8) & 0xFF
            i += 2
    return bytes(out)


def frames_from_video(video_path: Path, duration_sec: int = 4, preview_path: Path | None = None) -> list[bytes]:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=OUT_DIR) as td:
        pattern = str(Path(td) / "f_%02d.png")
        fps = max(ANIM_MAX_FRAMES / max(duration_sec, 1), 0.5)
        cmd = [
            "ffmpeg",
            "-y",
            "-i",
            str(video_path),
            "-vf",
            f"fps={fps:.4f},scale={ANIM_W}:{ANIM_H}:force_original_aspect_ratio=increase,crop={ANIM_W}:{ANIM_H}",
            "-frames:v",
            str(ANIM_MAX_FRAMES),
            pattern,
        ]
        try:
            subprocess.run(cmd, check=True, capture_output=True)
        except (subprocess.CalledProcessError, FileNotFoundError) as e:
            raise RuntimeError(f"ffmpeg frame extract failed: {e}") from e
        paths = sorted(Path(td).glob("f_*.png"))[:ANIM_MAX_FRAMES]
        if not paths:
            raise RuntimeError("No frames extracted from video")
        if preview_path is not None:
            preview_path.parent.mkdir(parents=True, exist_ok=True)
            Image.open(paths[0]).convert("RGB").save(preview_path, format="PNG")
        return [encode_frame_rgb565(Image.open(p)) for p in paths]


def run_ltx_job(prompt: str, duration_sec: int = 4, fps: int = 24, job_id: str | None = None) -> dict:
    """Submit to Comfy Cloud, download video, return paths + RGB565 frames."""
    api_key = os.environ.get("COMFY_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError("COMFY_API_KEY not configured on server")
    if not WORKFLOW_PATH.is_file():
        raise RuntimeError(f"Workflow missing: {WORKFLOW_PATH}")

    client = Comfy(api_key=api_key)
    wf = client.workflows.from_file(str(WORKFLOW_PATH))
    wf.set_input(NODE_PROMPT, "value", prompt)
    wf.set_input(NODE_DURATION, "value", int(duration_sec))
    wf.set_input(NODE_FPS, "value", int(fps))
    wf.set_input(NODE_ENHANCE, "value", False)

    try:
        job = client.run(wf)
    except Unauthorized as e:
        raise RuntimeError("Comfy Cloud unauthorized — check COMFY_API_KEY") from e
    except InsufficientCredits as e:
        raise RuntimeError("Comfy Cloud out of credits") from e
    except JobFailed as e:
        raise RuntimeError(f"Comfy job failed: {e}") from e

    outputs = list(job.get_outputs(NODE_SAVE_VIDEO))
    if not outputs:
        outputs = list(getattr(job, "outputs", []) or [])
    if not outputs:
        raise RuntimeError("Comfy job returned no video outputs")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    stem = job_id or str(getattr(job, "id", "ltx"))
    raw_name = str(getattr(outputs[0], "name", "ltx.mp4") or "ltx.mp4")
    safe_name = raw_name.replace("\\", "/").split("/")[-1] or "ltx.mp4"
    dest = OUT_DIR / f"{stem}_{safe_name}"
    preview = OUT_DIR / f"{stem}_preview.png"
    outputs[0].to_file(str(dest))

    frames = frames_from_video(dest, duration_sec=duration_sec, preview_path=preview)
    return {
        "comfy_job_id": getattr(job, "id", None),
        "video_path": str(dest),
        "preview_path": str(preview) if preview.is_file() else None,
        "frames": frames,
        "w": ANIM_W,
        "h": ANIM_H,
    }
