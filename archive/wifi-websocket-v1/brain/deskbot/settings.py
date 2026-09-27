from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import Any

import yaml
from pydantic import BaseModel, Field

BRAIN_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SETTINGS_PATH = BRAIN_ROOT / "config" / "settings.yaml"


class ServerSettings(BaseModel):
    host: str = "0.0.0.0"
    port: int = 8765
    path: str = "/deskbot"
    public_host: str = "127.0.0.1"


class OllamaSettings(BaseModel):
    base_url: str = "http://127.0.0.1:11434"
    gpt_oss_model: str = "gpt-oss:20b"
    fast_model: str = "qwen3.5:0.8b"
    behavior_model: str = "qwen3.5:0.8b"
    keep_alive: str = "24h"
    small_model_num_gpu: int = 0
    small_model_num_ctx: int = 2048
    behavior_temperature: float = 0.1
    fast_temperature: float = 0.6
    gpt_temperature: float = 0.7


class WarmupSettings(BaseModel):
    behavior_model: bool = True
    fast_model: bool = True
    gpt_oss: bool = True


class AudioSettings(BaseModel):
    codec: str = "pcm_s16le"
    sample_rate: int = 16000
    channels: int = 1
    frame_ms: int = 20

    @property
    def samples_per_frame(self) -> int:
        return int(self.sample_rate * (self.frame_ms / 1000.0))

    @property
    def bytes_per_frame(self) -> int:
        return self.samples_per_frame * 2 * self.channels


class SecuritySettings(BaseModel):
    device_token: str = "deskbot-local-dev"
    allowed_devices: list[str] = Field(default_factory=lambda: ["deskbot-01", "deskbot-sim"])


class HeartbeatSettings(BaseModel):
    interval_s: int = 3
    timeout_s: int = 12


class RobotSettings(BaseModel):
    head_yaw: list[float] = Field(default_factory=lambda: [-35.0, 35.0])
    head_pitch: list[float] = Field(default_factory=lambda: [-15.0, 20.0])
    default_speed: int = 35


class MemorySettings(BaseModel):
    sqlite_path: str = "data/deskbot.sqlite"


class Settings(BaseModel):
    server: ServerSettings = Field(default_factory=ServerSettings)
    ollama: OllamaSettings = Field(default_factory=OllamaSettings)
    warmup: WarmupSettings = Field(default_factory=WarmupSettings)
    audio: AudioSettings = Field(default_factory=AudioSettings)
    security: SecuritySettings = Field(default_factory=SecuritySettings)
    heartbeat: HeartbeatSettings = Field(default_factory=HeartbeatSettings)
    robot: RobotSettings = Field(default_factory=RobotSettings)
    memory: MemorySettings = Field(default_factory=MemorySettings)

    @property
    def sqlite_path(self) -> Path:
        path = Path(self.memory.sqlite_path)
        if not path.is_absolute():
            path = BRAIN_ROOT / path
        return path


def load_settings(path: Path | None = None) -> Settings:
    settings_path = path or DEFAULT_SETTINGS_PATH
    raw: dict[str, Any] = {}
    if settings_path.exists():
        raw = yaml.safe_load(settings_path.read_text(encoding="utf-8")) or {}
    return Settings.model_validate(raw)


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return load_settings()
