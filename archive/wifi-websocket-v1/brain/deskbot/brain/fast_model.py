from __future__ import annotations

import json
from collections.abc import AsyncIterator

from deskbot.brain.nova import NOVA_REPLY_SCHEMA, NovaReply, parse_nova_reply
from deskbot.brain.ollama_client import OllamaClient, OllamaError
from deskbot.brain.prompts import FAST_SYSTEM
from deskbot.settings import Settings

ESCALATE_TOKEN = "ESCALATE"


class FastModel:
    def __init__(self, client: OllamaClient, settings: Settings) -> None:
        self.client = client
        self.settings = settings

    async def complete(self, user_text: str, *, style: str = "neutral") -> NovaReply:
        messages = [
            {"role": "system", "content": FAST_SYSTEM},
            {
                "role": "user",
                "content": f"Speaking style: {style}\nUser: {user_text}",
            },
        ]
        try:
            response = await self.client.chat(
                self.settings.ollama.fast_model,
                messages,
                think=False,
                format=NOVA_REPLY_SCHEMA,
                options=self.client._small_options(self.settings.ollama.fast_temperature),
            )
            content = (response.get("message") or {}).get("content") or "{}"
            payload = json.loads(content) if isinstance(content, str) else content
            return parse_nova_reply(payload if isinstance(payload, dict) else {})
        except (OllamaError, ValueError, json.JSONDecodeError):
            return NovaReply(reply="", emotion="thinking", face="thinking_01", escalate=True)

    async def stream(self, user_text: str, *, style: str = "neutral") -> AsyncIterator[str]:
        reply = await self.complete(user_text, style=style)
        if reply.escalate and not reply.reply:
            yield ESCALATE_TOKEN
            return
        yield reply.reply
