#!/usr/bin/env python3
"""Kick off a live LTX job against deskbot.inmomentservices.com and poll until done."""

from __future__ import annotations

import json
import time
import urllib.error
import urllib.request
from pathlib import Path

BASE = "https://deskbot.inmomentservices.com"
OUT = Path(__file__).resolve().parents[1] / "comfy" / "out" / "live_test_job.json"


def req(method: str, path: str, data: dict | None = None, token: str | None = None):
    body = None if data is None else json.dumps(data).encode()
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) DeskbotLiveTest/1.0",
        "Origin": "https://deskbot.inmomentservices.com",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(BASE + path, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            return json.loads(response.read().decode())
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        raise SystemExit(f"HTTP {e.code} {path}: {detail}") from e


def main() -> None:
    email = f"nova.test.{int(time.time())}@inmomentservices.com"
    password = "DeskbotTest123!"
    reg = req(
        "POST",
        "/v1/auth/register",
        {"email": email, "password": password, "display_name": "NOVA Tester"},
    )
    token = reg["access_token"]
    print("registered", email, "user", reg["user_id"])

    prompt = (
        "Cute desk robot mascot NOVA fires a glowing blue kamehameha energy beam "
        "from left to right, fierce focused expression, locked camera, manga style, simple background"
    )
    job = req("POST", "/v1/ltx/jobs", {"prompt": prompt, "duration_sec": 4}, token=token)
    job_id = job["id"]
    print("job", job_id, job["status"])
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({"token": token, "jobId": job_id, "email": email}, indent=2), encoding="utf-8")

    deadline = time.time() + 15 * 60
    while time.time() < deadline:
        cur = req("GET", f"/v1/ltx/jobs/{job_id}", token=token)
        status = cur.get("status")
        print("status", status, "frames", cur.get("frame_count"))
        if status == "succeeded":
            frames = cur.get("frames_b64") or []
            print("SUCCESS frames=", len(frames), "w=", cur.get("frame_w"), "h=", cur.get("frame_h"))
            OUT.write_text(
                json.dumps(
                    {
                        "token": token,
                        "jobId": job_id,
                        "email": email,
                        "result": {
                            "status": status,
                            "frame_count": cur.get("frame_count"),
                            "frame_w": cur.get("frame_w"),
                            "frame_h": cur.get("frame_h"),
                            "prompt": cur.get("prompt"),
                        },
                    },
                    indent=2,
                ),
                encoding="utf-8",
            )
            return
        if status == "failed":
            raise SystemExit(f"FAILED: {cur.get('error')}")
        time.sleep(5)
    raise SystemExit("TIMEOUT waiting for job")


if __name__ == "__main__":
    main()
