from __future__ import annotations

import math
import struct

def rms_s16le(frame: bytes) -> float:
    if len(frame) < 2:
        return 0.0
    count = len(frame) // 2
    samples = struct.unpack("<" + "h" * count, frame[: count * 2])
    total = sum(sample * sample for sample in samples)
    return math.sqrt(total / count) / 32768.0


def mouth_open_from_rms(rms: float, previous: float = 0.0) -> float:
    target = min(1.0, max(0.0, (rms - 0.02) * 4.0))
    return previous * 0.6 + target * 0.4


class EnergyVad:
    def __init__(self, threshold: float = 0.035) -> None:
        self.threshold = threshold
        self.speech = False

    def update(self, frame: bytes) -> bool:
        energy = rms_s16le(frame)
        self.speech = energy >= self.threshold
        return self.speech
