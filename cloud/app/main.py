"""NOVA Deskbot cloud API — auth + LTX generation proxy for Comfy Cloud.

Deploy at https://deskbot.inmomentservices.com
"""

from __future__ import annotations

import os
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .db import init_db
from .routes_auth import router as auth_router
from .routes_ltx import router as ltx_router
from .routes_me import router as me_router

ROOT = Path(__file__).resolve().parents[1]


def _load_dotenv() -> None:
    path = ROOT / ".env"
    if not path.is_file():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        os.environ.setdefault(key.strip(), val.strip().strip('"').strip("'"))


@asynccontextmanager
async def lifespan(_app: FastAPI):
    _load_dotenv()
    init_db()
    yield


app = FastAPI(
    title="Deskbot Cloud",
    version="0.1.0",
    lifespan=lifespan,
)

origins = [
    o.strip()
    for o in os.environ.get(
        "CORS_ORIGINS",
        "http://localhost:*,https://deskbot.inmomentservices.com",
    ).split(",")
    if o.strip()
]
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"] if "*" in "".join(origins) else origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_router, prefix="/v1")
app.include_router(me_router, prefix="/v1")
app.include_router(ltx_router, prefix="/v1")


@app.get("/health")
def health():
    return {
        "ok": True,
        "service": "deskbot-cloud",
        "comfy_configured": bool(os.environ.get("COMFY_API_KEY")),
    }
