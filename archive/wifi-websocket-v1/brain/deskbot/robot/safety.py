from __future__ import annotations

from dataclasses import dataclass, field

from deskbot.settings import RobotSettings

JOINT_LIMITS = {
    "head_yaw": (-35.0, 35.0),
    "head_pitch": (-15.0, 20.0),
}

GESTURE_POSES: dict[str, dict[str, float]] = {
    "none": {},
    "nod": {"head_pitch": 8.0},
    "tiny_nod": {"head_pitch": 4.0},
    "tilt_left": {"head_yaw": -12.0, "head_pitch": 3.0},
    "tilt_right": {"head_yaw": 12.0, "head_pitch": 3.0},
    "look_left": {"head_yaw": -22.0},
    "look_right": {"head_yaw": 22.0},
    "recoil": {"head_pitch": -8.0, "head_yaw": -4.0},
    "perk_up": {"head_pitch": 10.0},
}


class SafetyError(ValueError):
    pass


def clamp(value: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, value))


def clamp_joint(joint: str, angle: float, settings: RobotSettings | None = None) -> float:
    if settings is not None and joint == "head_yaw":
        lo, hi = settings.head_yaw
    elif settings is not None and joint == "head_pitch":
        lo, hi = settings.head_pitch
    else:
        if joint not in JOINT_LIMITS:
            raise SafetyError(f"Unknown joint: {joint}")
        lo, hi = JOINT_LIMITS[joint]
    return clamp(float(angle), float(lo), float(hi))


def gesture_targets(gesture: str, settings: RobotSettings | None = None) -> dict[str, float]:
    if gesture not in GESTURE_POSES:
        raise SafetyError(f"Unknown gesture: {gesture}")
    return {
        joint: clamp_joint(joint, angle, settings)
        for joint, angle in GESTURE_POSES[gesture].items()
    }


@dataclass
class RobotPose:
    head_yaw: float = 0.0
    head_pitch: float = 0.0
    expression: str = "neutral"
    gaze: str = "center"
    state: str = "idle"
    energy: float = 0.4
    extra: dict[str, float] = field(default_factory=dict)
