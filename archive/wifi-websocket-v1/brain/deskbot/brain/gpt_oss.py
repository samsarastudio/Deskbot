from __future__ import annotations

from collections.abc import AsyncIterator

from deskbot.brain.ollama_client import OllamaClient
from deskbot.brain.prompts import GPT_SYSTEM
from deskbot.settings import Settings


class GptOss:
    def __init__(self, client: OllamaClient, settings: Settings) -> None:
        self.client = client
        self.settings = settings

    async def stream(
        self,
        user_text: str,
        *,
        style: str = "neutral",
        reasoning_level: str = "low",
    ) -> AsyncIterator[str]:
        think = reasoning_level if reasoning_level in {"low", "medium", "high"} else "low"
        messages = [
            {"role": "system", "content": GPT_SYSTEM},
            {
                "role": "user",
                "content": f"Speaking style: {style}\nUser: {user_text}",
            },
        ]
        async for token in self.client.chat_stream(
            self.settings.ollama.gpt_oss_model,
            messages,
            think=think,
            options={"temperature": self.settings.ollama.gpt_temperature},
        ):
            yield token
