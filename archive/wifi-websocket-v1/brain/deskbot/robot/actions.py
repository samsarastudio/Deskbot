from __future__ import annotations

from deskbot.gateway.protocol import BehaviorPlan, motion_message
from deskbot.robot.safety import RobotPose, clamp_joint, gesture_targets
from deskbot.settings import RobotSettings


class ActionCoordinator:
    def __init__(self, settings: RobotSettings) -> None:
        self.settings = settings
        self.pose = RobotPose()

    def apply_behavior(self, plan: BehaviorPlan) -> list[dict]:
        self.pose.expression = plan.expression
        self.pose.gaze = plan.gaze
        self.pose.energy = plan.energy
        messages = []
        for joint, angle in gesture_targets(plan.gesture, self.settings).items():
            setattr(self.pose, joint, angle)
            messages.append(motion_message(joint, angle, self.settings.default_speed))
        return messages

    def set_joint(self, joint: str, angle: float, speed: int | None = None) -> dict:
        clamped = clamp_joint(joint, angle, self.settings)
        setattr(self.pose, joint, clamped)
        return motion_message(joint, clamped, speed or self.settings.default_speed)

    def cancel_motion(self) -> list[dict]:
        messages = []
        for joint in ("head_yaw", "head_pitch"):
            messages.append(self.set_joint(joint, 0.0, speed=60))
        return messages

    def snapshot(self) -> dict:
        return {
            "head_yaw": self.pose.head_yaw,
            "head_pitch": self.pose.head_pitch,
            "expression": self.pose.expression,
            "gaze": self.pose.gaze,
            "state": self.pose.state,
            "energy": self.pose.energy,
        }
