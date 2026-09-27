from __future__ import annotations

import logging

from deskbot.brain.ollama_client import OllamaClient, OllamaError
from deskbot.brain.prompts import BEHAVIOR_SYSTEM, behavior_user_prompt
from deskbot.brain.reflex import heuristic_plan
from deskbot.gateway.protocol import BEHAVIOR_JSON_SCHEMA, BehaviorPlan
from deskbot.settings import Settings

log = logging.getLogger("deskbot.behavior")


class BehaviorBrain:
    def __init__(self, client: OllamaClient, settings: Settings) -> None:
        self.client = client
        self.settings = settings

    async def decide(
        self,
        user_text: str,
        *,
        previous_state: str,
        last_style: str,
        expression: str,
    ) -> BehaviorPlan:
        fallback = heuristic_plan(user_text)
        messages = [
            {"role": "system", "content": BEHAVIOR_SYSTEM},
            {
                "role": "user",
                "content": behavior_user_prompt(
                    user_text,
                    previous_state=previous_state,
                    last_style=last_style,
                    expression=expression,
                ),
            },
        ]
        try:
            response = await self.client.chat(
                self.settings.ollama.behavior_model,
                messages,
                stream=False,
                think=False,
                format=BEHAVIOR_JSON_SCHEMA,
                options=self.client._small_options(self.settings.ollama.behavior_temperature),
            )
            content = (response.get("message") or {}).get("content") or ""
            plan = BehaviorPlan.model_validate_json(content)
            if plan.route == "reflex":
                plan.route = fallback.route
            if plan.confidence < 0.35:
                plan.route = "brain"
                plan.reasoning_level = "medium"
            return plan
        except (OllamaError, ValueError) as exc:
            log.warning("Behavior model failed, using heuristic: %s", exc)
            return fallback
