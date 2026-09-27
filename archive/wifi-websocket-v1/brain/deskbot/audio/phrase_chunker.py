from __future__ import annotations

import re
from collections.abc import AsyncIterator, Callable, Awaitable

PHRASE_RE = re.compile(r"([^.!?]+[.!?]+|[^.!?,]+,)")


class PhraseChunker:
    def __init__(self, min_chars: int = 12) -> None:
        self.min_chars = min_chars
        self._buf = ""

    def reset(self) -> None:
        self._buf = ""

    def push(self, token: str) -> list[str]:
        self._buf += token
        phrases: list[str] = []
        while True:
            match = PHRASE_RE.search(self._buf)
            if not match:
                break
            phrase = match.group(0).strip()
            self._buf = self._buf[match.end() :].lstrip()
            if len(phrase) >= self.min_chars or phrase.endswith((".", "!", "?")):
                phrases.append(phrase)
            else:
                self._buf = phrase + " " + self._buf
                break
        return phrases

    def flush(self) -> str | None:
        leftover = self._buf.strip()
        self._buf = ""
        return leftover or None


async def stream_phrases(
    tokens: AsyncIterator[str],
    on_token: Callable[[str], Awaitable[None]] | None = None,
) -> AsyncIterator[str]:
    chunker = PhraseChunker()
    async for token in tokens:
        if on_token:
            await on_token(token)
        for phrase in chunker.push(token):
            yield phrase
    leftover = chunker.flush()
    if leftover:
        yield leftover
