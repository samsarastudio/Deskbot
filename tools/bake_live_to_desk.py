#!/usr/bin/env python3
"""Fetch latest successful live LTX job frames → manga_boot.h + GIF, then ready for flash."""

from __future__ import annotations

import base64
import json
import struct
import time
import urllib.request
from pathlib import Path

from PIL import Image

BASE = "https://deskbot.inmomentservices.com"
ROOT = Path(__file__).resolve().parents[1]
HDR = ROOT / "firmware" / "main" / "manga_boot.h"
GIF = ROOT / "app" / "assets" / "manga" / "ltx_kamehameha.gif"
OUT = ROOT / "tools" / "comfy" / "out"
W, H, FPS = 96, 52, 8


def req(method: str, path: str, data: dict | None = None, token: str | None = None):
    body = None if data is None else json.dumps(data).encode()
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "User-Agent": "Mozilla/5.0 DeskbotBake/1.0",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(BASE + path, data=body, headers=headers, method=method)
    with urllib.request.urlopen(request, timeout=180) as response:
        return json.loads(response.read().decode())


def rgb565_le_to_rgb(buf: bytes, w: int, h: int) -> Image.Image:
    im = Image.new("RGB", (w, h))
    px = im.load()
    i = 0
    for y in range(h):
        for x in range(w):
            v = buf[i] | (buf[i + 1] << 8)
            i += 2
            r = ((v >> 11) & 0x1F) * 255 // 31
            g = ((v >> 5) & 0x3F) * 255 // 63
            b = (v & 0x1F) * 255 // 31
            px[x, y] = (r, g, b)
    return im


def write_header(frames: list[bytes]) -> None:
    n = len(frames)
    pixels: list[int] = []
    for fr in frames:
        for i in range(0, len(fr), 2):
            pixels.append(fr[i] | (fr[i + 1] << 8))
    lines = [
        "#pragma once",
        "#include <stdint.h>",
        f"#define MANGA_BOOT_W {W}",
        f"#define MANGA_BOOT_H {H}",
        f"#define MANGA_BOOT_FRAMES {n}",
        f"#define MANGA_BOOT_FPS {FPS}",
        f"static const uint16_t MANGA_BOOT_PIX[MANGA_BOOT_W * MANGA_BOOT_H * MANGA_BOOT_FRAMES] = {{",
    ]
    row: list[str] = []
    for v in pixels:
        row.append(f"0x{v:04X}U")
        if len(row) == 10:
            lines.append("    " + ", ".join(row) + ",")
            row = []
    if row:
        lines.append("    " + ", ".join(row) + ",")
    if lines[-1].endswith(","):
        lines[-1] = lines[-1][:-1]
    lines.append("};")
    HDR.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("wrote", HDR, "frames", n)


def main() -> None:
    email = f"nova.bake.{int(time.time())}@inmomentservices.com"
    password = "DeskbotBake123!"
    reg = req(
        "POST",
        "/v1/auth/register",
        {"email": email, "password": password, "display_name": "Bake"},
    )
    token = reg["access_token"]
    # Prefer listing any succeeded jobs for this fresh user (none) — generate new quick? 
    # Use generate: short prompt, poll, bake.
    prompt = (
        "Cute desk robot mascot NOVA waves hello at the camera with both hands, "
        "cheerful expression, locked camera, manga style, simple background, clear silhouette"
    )
    job = req(
        "POST",
        "/v1/ltx/jobs",
        {"prompt": prompt, "title": "NOVA Wave", "duration_sec": 4},
        token=token,
    )
    job_id = job["id"]
    print("job", job_id, job["status"])
    deadline = time.time() + 15 * 60
    cur = job
    while time.time() < deadline:
        cur = req("GET", f"/v1/ltx/jobs/{job_id}", token=token)
        print("status", cur["status"], "frames", cur.get("frame_count"))
        if cur["status"] == "succeeded":
            break
        if cur["status"] == "failed":
            raise SystemExit(cur.get("error"))
        time.sleep(4)
    else:
        raise SystemExit("timeout")

    frames_b64 = cur.get("frames_b64") or []
    frames = [base64.b64decode(x) for x in frames_b64]
    if not frames:
        raise SystemExit("no frames")
    write_header(frames)

    imgs = [rgb565_le_to_rgb(f, W, H) for f in frames]
    OUT.mkdir(parents=True, exist_ok=True)
    GIF.parent.mkdir(parents=True, exist_ok=True)
    imgs[0].save(GIF, save_all=True, append_images=imgs[1:], duration=125, loop=0)
    print("gif", GIF)
    meta = {"jobId": job_id, "email": email, "title": cur.get("title"), "frames": len(frames)}
    (OUT / "bake_job.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
    print("done", meta)


if __name__ == "__main__":
    main()
