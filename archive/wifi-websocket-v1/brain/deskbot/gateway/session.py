from __future__ import annotations

import asyncio
import json
import logging
import time
from collections.abc import Awaitable, Callable
from typing import Any

from fastapi import WebSocket

from deskbot.audio.pcm import EnergyVad, mouth_open_from_rms, rms_s16le
from deskbot.brain.lcd_text import to_lcd_text
from deskbot.gateway.protocol import (
    audio_cancel_message,
    behavior_message,
    chat_message,
    command_message,
    face_message,
    hello_ack,
    model_message,
    ping_message,
    say_message,
    state_message,
)
from deskbot.robot.actions import ActionCoordinator
from deskbot.settings import Settings

log = logging.getLogger("deskbot.session")


class RobotSession:
    def __init__(self, websocket: WebSocket, settings: Settings, device_id: str, session_id: str) -> None:
        self.websocket = websocket
        self.settings = settings
        self.device_id = device_id
        self.session_id = session_id
        self.robot = ActionCoordinator(settings.robot)
        self.state = "idle"
        self.last_style = "neutral"
        self.expression = "neutral"
        self.face_id = "neutral_01"
        self.seq = 0
        self.stream_id = 0
        self.wifi_rssi: int | None = None
        self.last_rx = time.monotonic()
        self.capabilities: list[str] = []
        self.vad = EnergyVad()
        self.mouth = 0.0
        self.turn_task: asyncio.Task[Any] | None = None
        self._send_lock = asyncio.Lock()
        self.on_outbound: Callable[["RobotSession", dict[str, Any]], Awaitable[None]] | None = None

    def is_controller(self) -> bool:
        return self.device_id == "deskbot-sim" or "sim" in self.capabilities

    async def send_raw(self, payload: dict[str, Any]) -> None:
        async with self._send_lock:
            await self.websocket.send_text(json.dumps(payload))

    async def send(self, payload: dict[str, Any]) -> None:
        await self.send_raw(payload)
        if self.on_outbound is not None:
            await self.on_outbound(self, payload)

    async def send_hello_ack(self) -> None:
        audio = {
            "codec": self.settings.audio.codec,
            "sample_rate": self.settings.audio.sample_rate,
            "channels": self.settings.audio.channels,
            "frame_ms": self.settings.audio.frame_ms,
        }
        await self.send(
            hello_ack(
                self.session_id,
                audio,
                models={
                    "fast": self.settings.ollama.fast_model,
                    "brain": self.settings.ollama.gpt_oss_model,
                    "behavior": self.settings.ollama.behavior_model,
                },
            )
        )

    async def set_state(self, state: str) -> None:
        self.state = state
        self.robot.pose.state = state
        await self.send(state_message(state))

    async def send_face(
        self,
        expression: str,
        intensity: float = 0.6,
        transition_ms: int = 180,
        face: str | None = None,
    ) -> None:
        self.expression = expression
        self.face_id = face or f"{expression}_01"
        await self.send(face_message(expression, intensity, transition_ms, face=self.face_id))

    async def send_chat(self, speaker: str, text: str, emotion: str | None = None, face: str | None = None) -> None:
        await self.send(chat_message(speaker, to_lcd_text(text), emotion=emotion, face=face))

    async def send_command(self, action: str) -> None:
        await self.send(command_message(action))

    async def send_model(self, name: str, role: str, transferring: bool = False) -> None:
        await self.send(model_message(name, role, transferring))

    async def send_behavior(self, plan) -> None:
        self.seq += 1
        self.expression = plan.expression
        self.last_style = plan.speech_style
        await self.send(behavior_message(self.seq, plan))
        for motion in self.robot.apply_behavior(plan):
            await self.send(motion)

    async def say(self, text: str, final: bool = False) -> None:
        await self.send(say_message(text, final=final, stream_id=self.stream_id))

    async def cancel_output(self) -> None:
        if self.turn_task and not self.turn_task.done():
            self.turn_task.cancel()
        self.stream_id += 1
        await self.send(audio_cancel_message(self.stream_id))
        for motion in self.robot.cancel_motion():
            await self.send(motion)
        await self.set_state("listening")

    async def ping(self) -> None:
        await self.send(ping_message())

    def touch_rx(self) -> None:
        self.last_rx = time.monotonic()

    def timed_out(self) -> bool:
        return (time.monotonic() - self.last_rx) > self.settings.heartbeat.timeout_s

    def on_pcm(self, frame: bytes) -> dict[str, Any]:
        energy = rms_s16le(frame)
        speaking = self.vad.update(frame)
        self.mouth = mouth_open_from_rms(energy, self.mouth)
        return {
            "rms": round(energy, 4),
            "speech": speaking,
            "mouth": round(self.mouth, 3),
            "bytes": len(frame),
        }
