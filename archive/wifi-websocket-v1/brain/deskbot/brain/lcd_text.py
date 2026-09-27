from __future__ import annotations

import re

# Tiny LCD is 5x7 ASCII. Map fancy punctuation and emoji to the same glyphs
# the web panel and the robot will both show.
_PUNCT = {
    "\u2014": "-",
    "\u2013": "-",
    "\u2212": "-",
    "\u2018": "'",
    "\u2019": "'",
    "\u201c": '"',
    "\u201d": '"',
    "\u2026": "...",
    "\xa0": " ",
    "\u00a0": " ",
}

_EMOJI = {
    "😊": "^_^",
    "🙂": "^_^",
    "😁": "^o^",
    "😄": ":D",
    "😃": ":D",
    "😀": ":D",
    "😅": "^_^",
    "😆": "^o^",
    "😂": "^o^",
    "🤣": "^o^",
    "😉": "^-_",
    "😍": "<3",
    "🥰": "<3",
    "😘": "<3",
    "🤗": "^_^",
    "🤩": "^v^",
    "😇": "^_^",
    "😎": "B)",
    "😜": "^o^",
    "🤔": "-_-",
    "😐": "-_-",
    "😑": "-_-",
    "😴": "-_-",
    "😢": "T_T",
    "😭": "T_T",
    "😞": "T_T",
    "😔": "T_T",
    "🥺": "T_T",
    "😮": "o_o",
    "😲": "O_O",
    "😯": "o_o",
    "😳": "o_o",
    "😡": ">_<",
    "😤": ">_<",
    "😬": "-_-",
    "🙄": "-_-",
    "❤️": "<3",
    "❤": "<3",
    "♥": "<3",
    "💕": "<3",
    "💖": "<3",
    "💗": "<3",
    "💙": "<3",
    "💜": "<3",
    "💛": "<3",
    "💚": "<3",
    "🤍": "<3",
    "🖤": "<3",
    "♥️": "<3",
    "🫶": "<3",
    "🎉": "^v^",
    "🥳": "^v^",
    "✨": "",
    "🔥": "",
    "👍": "",
    "🙏": "",
}

_EMOJI_SORTED = tuple(sorted(_EMOJI.items(), key=lambda kv: len(kv[0]), reverse=True))
_SPACE_RE = re.compile(r"[ \t]{2,}")


def to_lcd_text(text: str | None) -> str:
    if not text:
        return ""
    out = str(text).replace("\r\n", "\n").replace("\r", "\n")
    for src, dst in _PUNCT.items():
        out = out.replace(src, dst)
    for src, dst in _EMOJI_SORTED:
        out = out.replace(src, f" {dst} " if dst else " ")
    cleaned: list[str] = []
    for ch in out:
        code = ord(ch)
        if ch == "\n" or 32 <= code <= 126:
            cleaned.append(ch)
    out = _SPACE_RE.sub(" ", "".join(cleaned))
    out = re.sub(r" *\n *", "\n", out)
    return out.strip()
