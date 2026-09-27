from __future__ import annotations

import random
import re
from dataclasses import dataclass

NOVA_NAME = "NOVA"
NOVA_MEANING = "Neural Orchestrated Virtual Assistant"

NOVA_EMOTIONS = [
    "neutral",
    "happy",
    "excited",
    "curious",
    "thinking",
    "surprised",
    "confused",
    "sad",
    "sleepy",
    "proud",
    "shy",
    "love",
    "laughing",
    "worried",
    "angry",
    "focused",
    "celebrating",
]

IDENTITY_REPLIES = [
    "Hi! I'm NOVA ^_^ your little Neural Orchestrated Virtual Assistant.",
    "I'm NOVA! ^_^ Your little desk buddy.",
    "NOVA! ^o^ Nice to meet you!",
    "I'm NOVA - tiny screen, big personality ^_^",
    "NOVA reporting in! ^v^",
]

IDENTITY_RE = re.compile(
    r"\b("
    r"what(?:'s| is|s)? your name"
    r"|who are you"
    r"|who're you"
    r"|who r u"
    r"|your name"
    r"|are you nova"
    r")\b",
    re.IGNORECASE,
)

NOVA_REPLY_SCHEMA: dict = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "reply": {"type": "string"},
        "emotion": {"type": "string", "enum": NOVA_EMOTIONS},
        "face": {"type": "string"},
        "action": {"type": "string"},
        "memory_action": {"type": "string"},
        "escalate": {"type": "boolean"},
    },
    "required": ["reply", "emotion", "face", "escalate"],
}


@dataclass
class NovaReply:
    reply: str
    emotion: str = "happy"
    face: str = "happy_01"
    action: str = "none"
    memory_action: str = "none"
    escalate: bool = False


def is_identity_question(text: str) -> bool:
    return bool(IDENTITY_RE.search(text or ""))


def identity_reply() -> NovaReply:
    return NovaReply(
        reply=random.choice(IDENTITY_REPLIES),
        emotion="happy",
        face="happy_01",
        action="name_intro",
    )


def default_face(emotion: str) -> str:
    base = (emotion or "neutral").strip().lower()
    if base not in NOVA_EMOTIONS:
        base = "neutral"
    return f"{base}_01"


def normalize_emotion(value: str | None) -> str:
    raw = (value or "neutral").strip().lower()
    aliases = {
        "amused": "laughing",
        "sympathetic": "sad",
        "skeptical": "confused",
        "celebrate": "celebrating",
        "love": "love",
    }
    raw = aliases.get(raw, raw)
    if raw not in NOVA_EMOTIONS:
        return "neutral"
    return raw


def normalize_face(face: str | None, emotion: str) -> str:
    raw = (face or "").strip().lower()
    emo = normalize_emotion(emotion)
    if not raw:
        return default_face(emo)
    if raw in NOVA_EMOTIONS:
        return default_face(raw)
    if "_" in raw:
        prefix = raw.split("_", 1)[0]
        if prefix in NOVA_EMOTIONS or prefix == "celebrate":
            return raw if prefix != "celebrate" else raw.replace("celebrate", "celebrating", 1)
    return default_face(emo)


def parse_nova_reply(payload: dict) -> NovaReply:
    emotion = normalize_emotion(str(payload.get("emotion") or "neutral"))
    face = default_face(emotion)
    reply = str(payload.get("reply") or "").strip()
    return NovaReply(
        reply=reply,
        emotion=emotion,
        face=face,
        action=str(payload.get("action") or "none"),
        memory_action=str(payload.get("memory_action") or "none"),
        escalate=bool(payload.get("escalate")),
    )
