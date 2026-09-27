"""Audio stubs for later phases: streaming STT, AEC, and Piper TTS."""

from __future__ import annotations


class StreamingSTT:
    async def feed(self, pcm: bytes) -> str | None:
        return None


class AcousticEchoCanceller:
    def process(self, near: bytes, far: bytes) -> bytes:
        return near


class TtsEngine:
    async def synthesize(self, text: str) -> bytes:
        return b""
