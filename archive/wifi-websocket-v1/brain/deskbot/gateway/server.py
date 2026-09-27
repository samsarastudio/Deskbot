from __future__ import annotations

import asyncio
import json
import logging
import uuid
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from deskbot.brain.behavior import BehaviorBrain
from deskbot.brain.fast_model import FastModel
from deskbot.brain.gpt_oss import GptOss
from deskbot.brain.ollama_client import OllamaClient, OllamaError
from deskbot.brain.pipeline import TurnPipeline
from deskbot.gateway.protocol import BehaviorPlan
from deskbot.gateway.session import RobotSession
from deskbot.memory.database import Memory
from deskbot.settings import Settings, get_settings

log = logging.getLogger("deskbot.server")
SIM_DIR = Path(__file__).resolve().parent.parent / "sim" / "static"


class TurnRequest(BaseModel):
    text: str
    device_id: str = "deskbot-sim"


class NullSocket:
    async def send_text(self, data: str) -> None:
        return None


class AppServices:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.ollama = OllamaClient(settings.ollama, timeout=180.0)
        self.memory = Memory(settings.sqlite_path)
        self.behavior = BehaviorBrain(self.ollama, settings)
        self.fast = FastModel(self.ollama, settings)
        self.gpt = GptOss(self.ollama, settings)
        self.pipeline = TurnPipeline(
            behavior=self.behavior,
            fast=self.fast,
            gpt=self.gpt,
            memory=self.memory,
        )
        self.sessions: dict[str, RobotSession] = {}
        self.ready = {
            "ollama": False,
            "behavior": False,
            "fast": False,
            "gpt_oss": False,
        }

    async def startup(self) -> None:
        await self.memory.open()
        try:
            version = await self.ollama.version()
            models = await self.ollama.tags()
            loaded = await self.ollama.ps()
            names = {m.get("name") for m in models}
            log.info("Ollama %s at %s", version, self.settings.ollama.base_url)
            log.info("Available models: %s", ", ".join(sorted(n for n in names if n)))
            log.info("Currently loaded: %s", ", ".join(m.get("name", "?") for m in loaded) or "none")
            self.ready["ollama"] = True
            if self.settings.warmup.behavior_model:
                self.ready["behavior"] = await self._warm(
                    self.settings.ollama.behavior_model, names, think=False, cpu=True
                )
                if self.settings.ollama.fast_model == self.settings.ollama.behavior_model:
                    self.ready["fast"] = self.ready["behavior"]
            asyncio.create_task(self._warmup_rest(names))
        except Exception as exc:
            log.exception("Ollama startup failed: %s", exc)

    async def shutdown(self) -> None:
        await self.memory.close()
        await self.ollama.aclose()

    async def _warmup_rest(self, names: set[str]) -> None:
        ollama = self.settings.ollama
        warmup = self.settings.warmup
        if warmup.fast_model and ollama.fast_model != ollama.behavior_model:
            self.ready["fast"] = await self._warm(ollama.fast_model, names, think=False, cpu=True)
        if warmup.gpt_oss:
            self.ready["gpt_oss"] = await self._warm(ollama.gpt_oss_model, names, think="low", cpu=False)

    async def _warm(self, model: str, names: set[str], think: bool | str, cpu: bool) -> bool:
        if model not in names and not any(name.startswith(model) for name in names):
            log.warning("Model %s is not installed on Ollama", model)
            return False
        try:
            await self.ollama.warmup(model, think=think, cpu=cpu)
            log.info("Warmed %s", model)
            return True
        except OllamaError as exc:
            log.warning("Warmup failed for %s: %s", model, exc)
            return False


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        logging.basicConfig(
            level=logging.INFO,
            format="%(asctime)s %(levelname)s %(name)s: %(message)s",
        )
        services = AppServices(settings)
        app.state.settings = settings
        app.state.services = services
        await services.startup()
        heartbeat = asyncio.create_task(_heartbeat_watch(services))
        try:
            yield
        finally:
            heartbeat.cancel()
            await services.shutdown()

    app = FastAPI(title="Deskbot Brain", version="0.1.0", lifespan=lifespan)
    if SIM_DIR.exists():
        app.mount("/static", StaticFiles(directory=SIM_DIR), name="static")

    @app.get("/")
    async def sim_index():
        index = SIM_DIR / "index.html"
        if index.exists():
            return FileResponse(index, headers={"Cache-Control": "no-store"})
        return JSONResponse({"name": "deskbot-brain", "ws": settings.server.path})

    @app.get("/health")
    async def health():
        services: AppServices = app.state.services
        try:
            loaded = await services.ollama.ps()
        except Exception as exc:
            return JSONResponse({"ok": False, "error": str(exc)}, status_code=503)
        return {
            "ok": True,
            "ready": services.ready,
            "loaded_models": [m.get("name") for m in loaded],
            "bind": f"{settings.server.host}:{settings.server.port}",
            "public_ws": f"ws://{settings.server.public_host}:{settings.server.port}{settings.server.path}",
            "ollama": settings.ollama.base_url,
            "models": {
                "fast": settings.ollama.fast_model,
                "brain": settings.ollama.gpt_oss_model,
                "behavior": settings.ollama.behavior_model,
            },
        }

    @app.get("/status")
    async def status():
        services: AppServices = app.state.services
        return {
            "ready": services.ready,
            "sessions": {
                sid: {
                    "device_id": session.device_id,
                    "state": session.state,
                    "pose": session.robot.snapshot(),
                }
                for sid, session in services.sessions.items()
            },
        }

    @app.post("/v1/turn")
    async def http_turn(body: TurnRequest):
        services: AppServices = app.state.services
        session = RobotSession(NullSocket(), settings, body.device_id, f"http-{uuid.uuid4().hex[:8]}")  # type: ignore[arg-type]
        result = await services.pipeline.handle_transcript(session, body.text)
        result["pose"] = session.robot.snapshot()
        return result

    @app.websocket(settings.server.path)
    async def deskbot_socket(websocket: WebSocket):
        services: AppServices = app.state.services
        await websocket.accept()
        session: RobotSession | None = None
        try:
            while True:
                message = await websocket.receive()
                if message.get("type") == "websocket.disconnect":
                    break
                if message.get("bytes") is not None:
                    if session is None:
                        continue
                    session.touch_rx()
                    info = session.on_pcm(message["bytes"])
                    await session.send({"type": "vad", **info})
                    continue
                text = message.get("text")
                if not text:
                    continue
                payload = json.loads(text)
                msg_type = payload.get("type")
                if msg_type == "hello":
                    session = await _hello(websocket, services, payload)
                    continue
                if session is None:
                    await websocket.send_text(json.dumps({"type": "error", "error": "say hello first"}))
                    continue
                session.touch_rx()
                await _dispatch(session, services, payload)
        except WebSocketDisconnect:
            pass
        except Exception:
            log.exception("WebSocket session crashed")
        finally:
            if session is not None:
                services.sessions.pop(session.session_id, None)
                await _broadcast_devices(services)

    return app


def _robots(services: AppServices) -> list[RobotSession]:
    return [session for session in services.sessions.values() if not session.is_controller()]


def _controllers(services: AppServices) -> list[RobotSession]:
    return [session for session in services.sessions.values() if session.is_controller()]


def _primary_target(services: AppServices, session: RobotSession) -> RobotSession:
    robots = _robots(services)
    return robots[0] if robots else session


async def _mirror_robot_to_ui(services: AppServices, origin: RobotSession, payload: dict[str, Any]) -> None:
    if origin.is_controller():
        return
    if payload.get("type") in {"ping", "hello_ack", "error"}:
        return
    for ui in _controllers(services):
        try:
            await ui.send_raw(payload)
        except Exception:
            log.debug("UI mirror failed", exc_info=True)


async def _broadcast_devices(services: AppServices) -> None:
    payload = {
        "type": "devices",
        "devices": [
            {
                "device_id": session.device_id,
                "state": session.state,
                "controller": session.is_controller(),
            }
            for session in services.sessions.values()
        ],
    }
    for ui in _controllers(services):
        try:
            await ui.send_raw(payload)
        except Exception:
            log.debug("device list send failed", exc_info=True)


async def _hello(websocket: WebSocket, services: AppServices, payload: dict[str, Any]) -> RobotSession | None:
    settings = services.settings
    device_id = str(payload.get("device_id") or "")
    token = payload.get("token")
    if device_id not in settings.security.allowed_devices:
        await websocket.send_text(json.dumps({"type": "error", "error": "unknown device"}))
        await websocket.close(code=4401)
        return None
    if token != settings.security.device_token:
        await websocket.send_text(json.dumps({"type": "error", "error": "bad token"}))
        await websocket.close(code=4401)
        return None
    session = RobotSession(websocket, settings, device_id, uuid.uuid4().hex)
    session.capabilities = list(payload.get("capabilities") or [])
    session.on_outbound = lambda origin, message: _mirror_robot_to_ui(services, origin, message)
    services.sessions[session.session_id] = session
    await session.send_hello_ack()
    await session.set_state("idle")
    if session.is_controller():
        robots = _robots(services)
        if robots:
            robot = robots[0]
            await session.send_raw({"type": "state", "state": robot.state})
            await session.send_raw(
                {
                    "type": "face",
                    "expression": robot.expression,
                    "intensity": 0.6,
                    "transition_ms": 80,
                }
            )
    await _broadcast_devices(services)
    log.info("Device %s connected session=%s caps=%s", device_id, session.session_id, session.capabilities)
    return session


async def _apply_event(target: RobotSession, event: str) -> None:
    if event == "wake":
        await target.set_state("listening")
        await target.send_face("curious", 0.7, 120)
    elif event == "touch":
        await target.send_face("happy", 0.8, 100)
        for motion in target.robot.apply_behavior(
            BehaviorPlan(
                route="reflex",
                expression="happy",
                gesture="tiny_nod",
                intensity=0.7,
            )
        ):
            await target.send(motion)
    elif event in {"stop", "mute"}:
        await target.cancel_output()
    elif event == "sleep":
        await target.set_state("sleep")
        await target.send_face("sleepy", 0.8, 180)


async def _apply_control(target: RobotSession, payload: dict[str, Any]) -> None:
    action = str(payload.get("action") or "")
    if action == "look_left":
        await target.send_behavior(
            BehaviorPlan(route="reflex", expression=target.expression or "neutral", gaze="left", gesture="look_left", intensity=0.7)
        )
    elif action == "look_right":
        await target.send_behavior(
            BehaviorPlan(route="reflex", expression=target.expression or "neutral", gaze="right", gesture="look_right", intensity=0.7)
        )
    elif action == "look_center":
        await target.send_behavior(
            BehaviorPlan(route="reflex", expression=target.expression or "neutral", gaze="user", gesture="none", intensity=0.5)
        )
        await target.send(target.robot.set_joint("head_yaw", 0.0, 40))
        await target.send(target.robot.set_joint("head_pitch", 0.0, 40))
    elif action == "expression":
        expression = str(payload.get("expression") or "neutral")
        await target.send_face(expression, float(payload.get("intensity") or 0.7), 160)
        gaze = payload.get("gaze")
        if gaze:
            await target.send_behavior(
                BehaviorPlan(route="reflex", expression=expression, gaze=str(gaze), gesture="none", intensity=0.6)
            )
    elif action == "heart":
        await target.send({"type": "fx", "name": "heart", "ms": 2600})
        await target.send_face("love", 1.0, 80)
    elif action == "gaze":
        await target.send_behavior(
            BehaviorPlan(
                route="reflex",
                expression=target.expression or "neutral",
                gaze=str(payload.get("gaze") or "user"),
                gesture="none",
                intensity=0.55,
            )
        )


async def _run_turn(services: AppServices, ui: RobotSession, target: RobotSession, text: str) -> None:
    result = await services.pipeline.handle_transcript(target, text)
    summary = {
        "type": "turn",
        "route": result.get("route"),
        "intent": result.get("intent"),
        "text": result.get("text") or "",
        "model": result.get("model") or "",
        "transferred": bool(result.get("transferred")),
    }
    await ui.send_raw(summary)
    if target is not ui:
        try:
            await target.send_raw(summary)
        except Exception:
            pass


async def _dispatch(session: RobotSession, services: AppServices, payload: dict[str, Any]) -> None:
    msg_type = payload.get("type")
    if msg_type in {"heartbeat", "pong"}:
        return
    if msg_type == "status":
        session.wifi_rssi = payload.get("wifi_rssi")
        if payload.get("state"):
            session.state = payload["state"]
        return
    target = _primary_target(services, session)
    if msg_type == "event":
        event = payload.get("event")
        if event:
            await _apply_event(target, str(event))
        return
    if msg_type == "control":
        await _apply_control(target, payload)
        return
    if msg_type == "user_text":
        text = str(payload.get("text") or "").strip()
        if not text:
            return
        if target.turn_task and not target.turn_task.done():
            await target.cancel_output()
        target.turn_task = asyncio.create_task(_run_turn(services, session, target, text))
        return


async def _heartbeat_watch(services: AppServices) -> None:
    try:
        while True:
            await asyncio.sleep(services.settings.heartbeat.interval_s)
            dead = [sid for sid, session in services.sessions.items() if session.timed_out()]
            for sid in dead:
                session = services.sessions.pop(sid, None)
                if session is None:
                    continue
                log.warning("Session timeout: %s", session.device_id)
                try:
                    await session.set_state("offline")
                    await session.websocket.close()
                except Exception:
                    pass
            for session in list(services.sessions.values()):
                try:
                    await session.ping()
                except Exception:
                    pass
    except asyncio.CancelledError:
        return


app = create_app()
