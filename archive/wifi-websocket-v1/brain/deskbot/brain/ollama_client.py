from __future__ import annotations

import json
import logging
from collections.abc import AsyncIterator
from typing import Any

import httpx

from deskbot.settings import OllamaSettings

log = logging.getLogger("deskbot.ollama")


class OllamaError(RuntimeError):
    pass


class OllamaClient:
    def __init__(self, settings: OllamaSettings, timeout: float = 120.0) -> None:
        self.settings = settings
        self._client = httpx.AsyncClient(
            base_url=settings.base_url.rstrip("/"),
            timeout=httpx.Timeout(timeout, connect=5.0),
        )

    async def aclose(self) -> None:
        await self._client.aclose()

    async def tags(self) -> list[dict[str, Any]]:
        response = await self._client.get("/api/tags")
        response.raise_for_status()
        return list(response.json().get("models", []))

    async def ps(self) -> list[dict[str, Any]]:
        response = await self._client.get("/api/ps")
        response.raise_for_status()
        return list(response.json().get("models", []))

    async def version(self) -> str:
        response = await self._client.get("/api/version")
        response.raise_for_status()
        return str(response.json().get("version", "unknown"))

    def _small_options(self, temperature: float) -> dict[str, Any]:
        return {
            "temperature": temperature,
            "num_gpu": self.settings.small_model_num_gpu,
            "num_ctx": self.settings.small_model_num_ctx,
        }

    async def chat(
        self,
        model: str,
        messages: list[dict[str, Any]],
        *,
        stream: bool = False,
        think: bool | str | None = False,
        format: dict[str, Any] | str | None = None,
        options: dict[str, Any] | None = None,
        keep_alive: str | None = None,
    ) -> dict[str, Any]:
        payload = self._payload(
            model,
            messages,
            stream=stream,
            think=think,
            format=format,
            options=options,
            keep_alive=keep_alive,
        )
        response = await self._client.post("/api/chat", json=payload)
        if response.status_code >= 400:
            raise OllamaError(f"{model} chat failed: {response.status_code} {response.text[:400]}")
        return response.json()

    async def chat_stream(
        self,
        model: str,
        messages: list[dict[str, Any]],
        *,
        think: bool | str | None = False,
        options: dict[str, Any] | None = None,
        keep_alive: str | None = None,
    ) -> AsyncIterator[str]:
        payload = self._payload(
            model,
            messages,
            stream=True,
            think=think,
            options=options,
            keep_alive=keep_alive,
        )
        async with self._client.stream("POST", "/api/chat", json=payload) as response:
            if response.status_code >= 400:
                body = (await response.aread()).decode("utf-8", errors="replace")
                raise OllamaError(f"{model} stream failed: {response.status_code} {body[:400]}")
            async for line in response.aiter_lines():
                if not line:
                    continue
                chunk = json.loads(line)
                if chunk.get("error"):
                    raise OllamaError(str(chunk["error"]))
                content = (chunk.get("message") or {}).get("content") or ""
                if content:
                    yield content
                if chunk.get("done"):
                    return

    async def warmup(self, model: str, *, think: bool | str | None = False, cpu: bool = False) -> None:
        options = {"num_predict": 1, "temperature": 0}
        if cpu:
            options["num_gpu"] = self.settings.small_model_num_gpu
            options["num_ctx"] = min(512, self.settings.small_model_num_ctx)
        log.info("Warming %s (cpu=%s think=%s)", model, cpu, think)
        await self.chat(
            model,
            [{"role": "user", "content": "ping"}],
            stream=False,
            think=think,
            options=options,
        )

    def _payload(
        self,
        model: str,
        messages: list[dict[str, Any]],
        *,
        stream: bool,
        think: bool | str | None,
        format: dict[str, Any] | str | None = None,
        options: dict[str, Any] | None = None,
        keep_alive: str | None = None,
    ) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "model": model,
            "messages": messages,
            "stream": stream,
            "keep_alive": keep_alive or self.settings.keep_alive,
        }
        if think is not None:
            payload["think"] = think
        if format is not None:
            payload["format"] = format
        if options:
            payload["options"] = options
        return payload
