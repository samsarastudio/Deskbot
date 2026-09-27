#!/usr/bin/env python3
"""Run the LTX-2.5 T2V workflow on Comfy Cloud (or local via COMFY_BASE_URL).

Prereqs:
  1. Paid Comfy Cloud plan + API key from https://platform.comfy.org
  2. pip install -r tools/comfy/requirements.txt
  3. Set COMFY_API_KEY (or pass --api-key)

Workflow must be API format (File → Export Workflow (API)).
This repo ships tools/comfy/workflows/video_ltx2_5_t2v.json from that export.

Node IDs (from the exported graph):
  405:376  PrimitiveStringMultiline  → prompt text (.value)
  405:362  PrimitiveInt              → duration seconds
  405:361  PrimitiveInt              → frame rate
  405:383  PrimitiveBoolean          → prompt enhance
  75       SaveVideo                 → output video
"""

from __future__ import annotations

import argparse
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

from comfy_sdk import Comfy
from comfy_sdk.exceptions import InsufficientCredits, JobFailed, Unauthorized

ROOT = Path(__file__).resolve().parent
DEFAULT_WORKFLOW = ROOT / "workflows" / "video_ltx2_5_t2v.json"
DEFAULT_OUT_DIR = ROOT / "out"

# Stable node IDs from video_ltx2_5_t2v.json
NODE_PROMPT = "405:376"
NODE_DURATION = "405:362"
NODE_FPS = "405:361"
NODE_ENHANCE = "405:383"
NODE_SAVE_VIDEO = "75"


def _load_dotenv(path: Path) -> None:
    if not path.is_file():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        key = key.strip()
        val = val.strip().strip('"').strip("'")
        os.environ.setdefault(key, val)


def _parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Run LTX-2.5 T2V on Comfy Cloud")
    p.add_argument(
        "--workflow",
        type=Path,
        default=DEFAULT_WORKFLOW,
        help="API-format workflow JSON",
    )
    p.add_argument(
        "--prompt",
        type=str,
        default=None,
        help="Override positive prompt (node 405:376)",
    )
    p.add_argument(
        "--prompt-file",
        type=Path,
        default=None,
        help="Read prompt from a text file",
    )
    p.add_argument("--duration", type=int, default=None, help="Clip length in seconds")
    p.add_argument("--fps", type=int, default=None, help="Frame rate")
    p.add_argument(
        "--enhance",
        action=argparse.BooleanOptionalAction,
        default=None,
        help="Enable/disable LTX prompt enhancer",
    )
    p.add_argument(
        "--out-dir",
        type=Path,
        default=DEFAULT_OUT_DIR,
        help="Directory for downloaded videos",
    )
    p.add_argument(
        "--api-key",
        default=None,
        help="Comfy API key (else COMFY_API_KEY / .env)",
    )
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="Patch workflow locally and print summary; do not submit",
    )
    return p.parse_args()


def main() -> int:
    _load_dotenv(ROOT / ".env")
    _load_dotenv(ROOT.parent.parent / ".env")
    args = _parse_args()

    if not args.workflow.is_file():
        print(f"Workflow not found: {args.workflow}", file=sys.stderr)
        return 2

    prompt = args.prompt
    if args.prompt_file is not None:
        prompt = args.prompt_file.read_text(encoding="utf-8").strip()

    api_key = args.api_key or os.environ.get("COMFY_API_KEY") or os.environ.get("COMFY_CLOUD_API_KEY")
    base = (os.environ.get("COMFY_BASE_URL") or "").strip() or "https://cloud.comfy.org (default)"

    # Dry-run only needs local JSON patching; Cloud still requires a real key to submit.
    client = Comfy(api_key=api_key or ("dry-run" if args.dry_run else None))
    wf = client.workflows.from_file(str(args.workflow))

    if prompt is not None:
        wf.set_input(NODE_PROMPT, "value", prompt)
    if args.duration is not None:
        wf.set_input(NODE_DURATION, "value", int(args.duration))
    if args.fps is not None:
        wf.set_input(NODE_FPS, "value", int(args.fps))
    if args.enhance is not None:
        wf.set_input(NODE_ENHANCE, "value", bool(args.enhance))

    graph = wf.json
    prompt_preview = graph.get(NODE_PROMPT, {}).get("inputs", {}).get("value", "")
    duration = graph.get(NODE_DURATION, {}).get("inputs", {}).get("value")
    fps = graph.get(NODE_FPS, {}).get("inputs", {}).get("value")

    print(f"target:   {base}")
    print(f"workflow: {args.workflow.name}")
    print(f"duration: {duration}s  fps: {fps}")
    print(f"prompt:   {str(prompt_preview)[:160]}{'…' if len(str(prompt_preview)) > 160 else ''}")

    if args.dry_run:
        print("dry-run: workflow patched OK, not submitted")
        return 0

    if not api_key and "127.0.0.1" not in str(os.environ.get("COMFY_BASE_URL", "")):
        print(
            "Missing COMFY_API_KEY. Create one at https://platform.comfy.org "
            "and put it in tools/comfy/.env",
            file=sys.stderr,
        )
        return 2

    args.out_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")

    try:
        print("submitting…")
        job = client.run(wf)
    except Unauthorized:
        print("Unauthorized: check COMFY_API_KEY / paid Cloud subscription.", file=sys.stderr)
        return 1
    except InsufficientCredits:
        print("Insufficient credits on Comfy Cloud.", file=sys.stderr)
        return 1
    except JobFailed as e:
        print(f"Job failed: {e}", file=sys.stderr)
        return 1

    outputs = list(job.get_outputs(NODE_SAVE_VIDEO))
    if not outputs:
        # Fallback: any video-like output on the job
        outputs = [o for o in getattr(job, "outputs", []) or []]
        print(f"no outputs on node {NODE_SAVE_VIDEO}; job has {len(outputs)} total output(s)")

    saved: list[Path] = []
    for i, out in enumerate(outputs):
        name = getattr(out, "name", None) or f"ltx_t2v_{stamp}_{i}.mp4"
        dest = args.out_dir / Path(name).name
        if dest.exists():
            dest = args.out_dir / f"{dest.stem}_{stamp}{dest.suffix}"
        out.to_file(str(dest))
        saved.append(dest)
        print(f"saved: {dest}")

    if not saved:
        print("Job finished but no video files were returned.", file=sys.stderr)
        return 1

    print(f"done ({len(saved)} file(s))")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
