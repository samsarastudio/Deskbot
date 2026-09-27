from __future__ import annotations

import time
from enum import Enum
from typing import Any, Literal

from pydantic import BaseModel, Field


PROTOCOL_VERSION = 1

DeviceState = Literal[
    "boot",
    "connect_wifi",
    "connect_brain",
    "idle",
    "sleep",
    "listening",
    "streaming_input",
    "thinking",
    "speaking",
    "offline",
]

Expression = Literal[
    "neutral",
    "happy",
    "amused",
    "curious",
    "excited",
    "surprised",
    "sympathetic",
    "focused",
    "skeptical",
    "confused",
    "sleepy",
    "love",
    "thinking",
    "sad",
    "proud",
    "shy",
    "laughing",
    "worried",
    "angry",
    "celebrating",
]

Gaze = Literal["user", "center", "left", "right", "down", "wander"]

Gesture = Literal[
    "none",
    "nod",
    "tiny_nod",
    "tilt_left",
    "tilt_right",
    "look_left",
    "look_right",
    "recoil",
    "perk_up",
]

SpeechStyle = Literal["neutral", "warm", "cheerful", "calm", "serious", "playful"]
Route = Literal["reflex", "fast", "brain"]
ReasoningLevel = Literal["low", "medium", "high"]


class HelloMessage(BaseModel):
    type: Literal["hello"] = "hello"
    device_id: str
    protocol: int = PROTOCOL_VERSION
    token: str | None = None
    capabilities: list[str] = Field(default_factory=list)


class EventMessage(BaseModel):
    type: Literal["event"] = "event"
    event: str
    zone: str | None = None
    data: dict[str, Any] | None = None


class StatusMessage(BaseModel):
    type: Literal["status"] = "status"
    wifi_rssi: int | None = None
    state: str | None = None
    sd_free_mb: int | None = None


class HeartbeatMessage(BaseModel):
    type: Literal["heartbeat"] = "heartbeat"
    ts_ms: int | None = None


class UserTextMessage(BaseModel):
    type: Literal["user_text"] = "user_text"
    text: str


class BehaviorPlan(BaseModel):
    route: Route = "fast"
    expression: Expression = "neutral"
    intensity: float = Field(default=0.5, ge=0.0, le=1.0)
    gaze: Gaze = "user"
    gesture: Gesture = "none"
    energy: float = Field(default=0.45, ge=0.0, le=1.0)
    speech_style: SpeechStyle = "neutral"
    reasoning_level: ReasoningLevel = "low"
    intent: str = "conversation"
    confidence: float = Field(default=0.7, ge=0.0, le=1.0)
    tools_allowed: list[str] = Field(default_factory=list)


BEHAVIOR_JSON_SCHEMA: dict[str, Any] = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "route": {"type": "string", "enum": ["reflex", "fast", "brain"]},
        "expression": {
            "type": "string",
            "enum": [
                "neutral",
                "happy",
                "amused",
                "curious",
                "excited",
                "surprised",
                "sympathetic",
                "focused",
                "skeptical",
                "confused",
                "sleepy",
                "love",
                "thinking",
                "sad",
                "proud",
                "shy",
                "laughing",
                "worried",
                "angry",
                "celebrating",
            ],
        },
        "intensity": {"type": "number", "minimum": 0.0, "maximum": 1.0},
        "gaze": {
            "type": "string",
            "enum": ["user", "center", "left", "right", "down", "wander"],
        },
        "gesture": {
            "type": "string",
            "enum": [
                "none",
                "nod",
                "tiny_nod",
                "tilt_left",
                "tilt_right",
                "look_left",
                "look_right",
                "recoil",
                "perk_up",
            ],
        },
        "energy": {"type": "number", "minimum": 0.0, "maximum": 1.0},
        "speech_style": {
            "type": "string",
            "enum": ["neutral", "warm", "cheerful", "calm", "serious", "playful"],
        },
        "reasoning_level": {"type": "string", "enum": ["low", "medium", "high"]},
        "intent": {"type": "string"},
        "confidence": {"type": "number", "minimum": 0.0, "maximum": 1.0},
        "tools_allowed": {"type": "array", "items": {"type": "string"}},
    },
    "required": [
        "route",
        "expression",
        "intensity",
        "gaze",
        "gesture",
        "energy",
        "speech_style",
    ],
}


class FaceLayer(str, Enum):
    REFLEX = "reflex"
    EMOTION = "emotion"
    SPEECH = "speech"
    MICRO = "micro"


def hello_ack(session_id: str, audio: dict[str, Any], models: dict[str, str] | None = None) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "type": "hello_ack",
        "session_id": session_id,
        "protocol": PROTOCOL_VERSION,
        "audio": audio,
        "unix": int(time.time()),
        "tz": "EST5EDT,M3.2.0,M11.1.0",
    }
    if models:
        payload["models"] = models
    return payload


def model_message(name: str, role: str, transferring: bool = False) -> dict[str, Any]:
    return {
        "type": "model",
        "name": name,
        "role": role,
        "transferring": transferring,
    }


def face_message(
    expression: str,
    intensity: float = 0.6,
    transition_ms: int = 180,
    face: str | None = None,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "type": "face",
        "expression": expression,
        "emotion": expression,
        "intensity": intensity,
        "transition_ms": transition_ms,
        "face": face or f"{expression}_01",
    }
    return payload


def chat_message(speaker: str, text: str, emotion: str | None = None, face: str | None = None) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "type": "chat",
        "speaker": speaker,
        "text": text,
    }
    if emotion:
        payload["emotion"] = emotion
        payload["expression"] = emotion
    if face:
        payload["face"] = face
    return payload


def command_message(action: str) -> dict[str, Any]:
    return {"type": "command", "action": action}


def behavior_message(seq: int, plan: BehaviorPlan, transition_ms: int = 180) -> dict[str, Any]:
    return {
        "type": "behavior",
        "seq": seq,
        "expression": plan.expression,
        "intensity": plan.intensity,
        "gaze": plan.gaze,
        "gesture": plan.gesture,
        "energy": plan.energy,
        "speech_style": plan.speech_style,
        "transition_ms": transition_ms,
    }


def motion_message(joint: str, angle: float, speed: int) -> dict[str, Any]:
    return {
        "type": "motion",
        "joint": joint,
        "angle": round(angle, 2),
        "speed": speed,
    }


def state_message(state: str) -> dict[str, Any]:
    return {"type": "state", "state": state}


def say_message(text: str, final: bool = False, stream_id: int | None = None) -> dict[str, Any]:
    payload: dict[str, Any] = {"type": "say", "text": text, "final": final}
    if stream_id is not None:
        payload["stream_id"] = stream_id
    return payload


def audio_start_message(stream_id: int, sample_rate: int = 16000) -> dict[str, Any]:
    return {
        "type": "audio_start",
        "stream_id": stream_id,
        "sample_rate": sample_rate,
    }


def audio_cancel_message(stream_id: int) -> dict[str, Any]:
    return {"type": "audio_cancel", "stream_id": stream_id}


def ping_message() -> dict[str, Any]:
    return {"type": "ping"}
