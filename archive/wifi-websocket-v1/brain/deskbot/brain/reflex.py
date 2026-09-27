from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any

from deskbot.gateway.protocol import BehaviorPlan

STOP_RE = re.compile(
    r"\b(stop|shut up|be quiet|cancel|enough|halt|abort)\b",
    re.IGNORECASE,
)
WAKE_RE = re.compile(
    r"^\s*((?:hey |hi )?(?:nova|deskbot)|wake(?: up)?)\s*[.!?]*\s*$",
    re.IGNORECASE,
)
SLEEP_RE = re.compile(r"\b(go to sleep|sleep now|rest now)\b", re.IGNORECASE)
MUTE_RE = re.compile(r"\b(mute|silence)\b", re.IGNORECASE)
VOLUME_UP_RE = re.compile(r"\b(volume up|louder|speak up)\b", re.IGNORECASE)
VOLUME_DOWN_RE = re.compile(r"\b(volume down|quieter|softer)\b", re.IGNORECASE)
LOOK_LEFT_RE = re.compile(r"\b(look left|turn (?:your )?head left)\b", re.IGNORECASE)
LOOK_RIGHT_RE = re.compile(r"\b(look right|turn (?:your )?head right)\b", re.IGNORECASE)
NOD_RE = re.compile(r"\b(nod(?: your head)?)\b", re.IGNORECASE)
BLINK_RE = re.compile(r"\bblink\b", re.IGNORECASE)
STATUS_RE = re.compile(r"\b(status|battery|are you online|how are you connected)\b", re.IGNORECASE)
TIME_RE = re.compile(
    r"\b((what(?:'s| is) the time)|what time is it|tell me the time)\b",
    re.IGNORECASE,
)


@dataclass
class ReflexResult:
    intent: str
    speak: str | None = None
    plan: BehaviorPlan = field(default_factory=BehaviorPlan)
    actions: list[dict[str, Any]] = field(default_factory=list)
    cancel: bool = False


def is_emergency(text: str) -> bool:
    return bool(STOP_RE.search(text.strip()))


def match_reflex(text: str, *, wifi_rssi: int | None = None) -> ReflexResult | None:
    raw = text.strip()
    if not raw:
        return None

    if is_emergency(raw):
        return ReflexResult(
            intent="stop",
            speak=None,
            cancel=True,
            plan=BehaviorPlan(
                route="reflex",
                expression="focused",
                intensity=0.8,
                gaze="user",
                gesture="none",
                energy=0.2,
                speech_style="serious",
                intent="stop",
                confidence=1.0,
            ),
        )

    if WAKE_RE.match(raw):
        return ReflexResult(
            intent="wake",
            plan=BehaviorPlan(
                route="reflex",
                expression="happy",
                intensity=0.7,
                gaze="user",
                gesture="perk_up",
                energy=0.7,
                speech_style="warm",
                intent="wake",
                confidence=1.0,
            ),
        )

    if SLEEP_RE.search(raw):
        return ReflexResult(
            intent="sleep",
            speak="Going to sleep.",
            plan=BehaviorPlan(
                route="reflex",
                expression="sleepy",
                intensity=0.8,
                gaze="down",
                gesture="none",
                energy=0.1,
                speech_style="calm",
                intent="sleep",
                confidence=1.0,
            ),
        )

    if MUTE_RE.search(raw):
        return ReflexResult(
            intent="mute",
            cancel=True,
            plan=BehaviorPlan(route="reflex", expression="neutral", intent="mute", confidence=1.0),
        )

    if VOLUME_UP_RE.search(raw):
        return ReflexResult(
            intent="volume_up",
            speak="Okay, louder.",
            plan=BehaviorPlan(route="reflex", expression="happy", gesture="tiny_nod", intent="volume_up", confidence=1.0),
        )

    if VOLUME_DOWN_RE.search(raw):
        return ReflexResult(
            intent="volume_down",
            speak="Okay, quieter.",
            plan=BehaviorPlan(route="reflex", expression="neutral", intent="volume_down", confidence=1.0),
        )

    if LOOK_LEFT_RE.search(raw):
        return ReflexResult(
            intent="look_left",
            plan=BehaviorPlan(
                route="reflex",
                expression="curious",
                gaze="left",
                gesture="look_left",
                intent="look_left",
                confidence=1.0,
            ),
        )

    if LOOK_RIGHT_RE.search(raw):
        return ReflexResult(
            intent="look_right",
            plan=BehaviorPlan(
                route="reflex",
                expression="curious",
                gaze="right",
                gesture="look_right",
                intent="look_right",
                confidence=1.0,
            ),
        )

    if NOD_RE.search(raw):
        return ReflexResult(
            intent="nod",
            plan=BehaviorPlan(route="reflex", expression="happy", gesture="nod", intent="nod", confidence=1.0),
        )

    if BLINK_RE.search(raw):
        return ReflexResult(
            intent="blink",
            plan=BehaviorPlan(route="reflex", expression="neutral", gesture="none", intent="blink", confidence=1.0),
        )

    if TIME_RE.search(raw):
        now = datetime.now().strftime("%I:%M %p").lstrip("0")
        return ReflexResult(
            intent="time",
            speak=f"It's {now}.",
            plan=BehaviorPlan(
                route="reflex",
                expression="neutral",
                gesture="tiny_nod",
                speech_style="calm",
                intent="time",
                confidence=1.0,
            ),
        )

    if STATUS_RE.search(raw):
        rssi = f"{wifi_rssi} dBm" if wifi_rssi is not None else "unknown"
        return ReflexResult(
            intent="status",
            speak=f"I'm online. Wi-Fi signal {rssi}.",
            plan=BehaviorPlan(
                route="reflex",
                expression="focused",
                gesture="tiny_nod",
                intent="status",
                confidence=1.0,
            ),
        )

    return None


QUESTION_RE = re.compile(r"\?\s*$")
EXCLAIM_RE = re.compile(r"!\s*$")
NEGATIVE_RE = re.compile(
    r"\b(error|fail|crash|broken|wrong|bug|exception|can't|cannot)\b",
    re.IGNORECASE,
)
COMPLEX_RE = re.compile(
    r"\b(blender|python|code|script|why|explain|design|plan|research|implement|debug|mcp)\b",
    re.IGNORECASE,
)


def heuristic_plan(text: str) -> BehaviorPlan:
    if NEGATIVE_RE.search(text) or COMPLEX_RE.search(text):
        return BehaviorPlan(
            route="brain",
            expression="focused",
            intensity=0.7,
            gaze="center",
            gesture="tilt_left",
            energy=0.4,
            speech_style="serious",
            reasoning_level="medium",
            intent="complex",
            confidence=0.55,
        )
    if EXCLAIM_RE.search(text):
        return BehaviorPlan(
            route="fast",
            expression="excited",
            intensity=0.75,
            gaze="user",
            gesture="perk_up",
            energy=0.8,
            speech_style="cheerful",
            intent="exclaim",
            confidence=0.6,
        )
    if QUESTION_RE.search(text):
        return BehaviorPlan(
            route="fast",
            expression="curious",
            intensity=0.65,
            gaze="user",
            gesture="tilt_right",
            energy=0.5,
            speech_style="warm",
            intent="question",
            confidence=0.6,
        )
    return BehaviorPlan(
        route="fast",
        expression="neutral",
        intensity=0.45,
        gaze="user",
        gesture="none",
        energy=0.4,
        speech_style="neutral",
        intent="conversation",
        confidence=0.5,
    )
