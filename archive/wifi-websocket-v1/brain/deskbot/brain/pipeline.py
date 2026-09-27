from __future__ import annotations

import logging
from collections.abc import AsyncIterator

from deskbot.audio.phrase_chunker import stream_phrases
from deskbot.brain.behavior import BehaviorBrain
from deskbot.brain.fast_model import ESCALATE_TOKEN, FastModel
from deskbot.brain.gpt_oss import GptOss
from deskbot.brain.nova import NovaReply, identity_reply, is_identity_question
from deskbot.brain.reflex import heuristic_plan, is_emergency, match_reflex
from deskbot.gateway.protocol import BehaviorPlan
from deskbot.gateway.session import RobotSession
from deskbot.memory.database import Memory

log = logging.getLogger("deskbot.pipeline")


class TurnPipeline:
    def __init__(
        self,
        *,
        behavior: BehaviorBrain,
        fast: FastModel,
        gpt: GptOss,
        memory: Memory,
    ) -> None:
        self.behavior = behavior
        self.fast = fast
        self.gpt = gpt
        self.memory = memory

    def _fast_name(self) -> str:
        return self.fast.settings.ollama.fast_model

    def _brain_name(self) -> str:
        return self.gpt.settings.ollama.gpt_oss_model

    async def handle_transcript(self, session: RobotSession, text: str) -> dict:
        text = text.strip()
        if not text:
            return {"route": "none", "text": "", "model": "", "transferred": False}

        await session.send_chat("user", text)

        if is_emergency(text):
            await session.cancel_output()
            await session.send_face("focused", 0.8, 80, face="focused_01")
            await self.memory.add_turn(session.device_id, "user", text, "reflex")
            return {"route": "reflex", "intent": "stop", "text": "", "model": "", "transferred": False}

        if is_identity_question(text):
            nova = identity_reply()
            await session.send_model(self._fast_name(), "fast")
            await self._deliver_nova(session, nova)
            await self.memory.add_turn(session.device_id, "user", text, "fast")
            await self.memory.add_turn(session.device_id, "assistant", nova.reply, "fast")
            await session.set_state("idle")
            return {
                "route": "fast",
                "intent": "identity",
                "text": nova.reply,
                "emotion": nova.emotion,
                "face": nova.face,
                "model": self._fast_name(),
                "transferred": False,
            }

        reflex = match_reflex(text, wifi_rssi=session.wifi_rssi)
        if reflex:
            if reflex.cancel:
                await session.cancel_output()
            await session.send_behavior(reflex.plan)
            if reflex.intent == "sleep":
                await session.set_state("sleep")
            elif reflex.intent == "wake":
                await session.set_state("listening")
            if reflex.speak:
                await session.set_state("speaking")
                await session.send_chat("nova", reflex.speak, reflex.plan.expression, f"{reflex.plan.expression}_01")
                await session.say(reflex.speak, final=True)
                await session.set_state("idle")
            await self.memory.add_turn(session.device_id, "user", text, "reflex")
            if reflex.speak:
                await self.memory.add_turn(session.device_id, "assistant", reflex.speak, "reflex")
            return {"route": "reflex", "intent": reflex.intent, "text": reflex.speak or "", "model": "", "transferred": False}

        await session.set_state("thinking")
        provisional = heuristic_plan(text)
        await session.send_face(provisional.expression, provisional.intensity, 120)

        plan = await self.behavior.decide(
            text,
            previous_state=session.state,
            last_style=session.last_style,
            expression=session.expression,
        )
        await session.send_behavior(plan)

        transferred = False
        if plan.route == "fast":
            await session.send_model(self._fast_name(), "fast")
            answer, used_route = await self._fast_then_maybe_brain(session, text, plan)
            transferred = used_route == "brain"
        else:
            await session.send_model(self._brain_name(), "brain", transferring=True)
            answer = await self._speak_stream(session, self.gpt.stream(text, style=plan.speech_style, reasoning_level=plan.reasoning_level))
            used_route = "brain"
            transferred = True
            if answer:
                await session.send_chat("nova", answer, plan.expression, f"{plan.expression}_01")

        model = self._brain_name() if used_route == "brain" else self._fast_name()
        if used_route == "brain":
            await session.send_model(model, "brain", transferring=False)

        await self.memory.add_turn(session.device_id, "user", text, used_route)
        if answer:
            await self.memory.add_turn(session.device_id, "assistant", answer, used_route)
        await session.set_state("idle")
        return {
            "route": used_route,
            "intent": plan.intent,
            "plan": plan.model_dump(),
            "text": answer,
            "model": model,
            "transferred": transferred,
        }

    async def _deliver_nova(self, session: RobotSession, nova: NovaReply) -> None:
        await session.send_face(nova.emotion, 0.85, 120, face=nova.face)
        await session.send_chat("nova", nova.reply, nova.emotion, nova.face)
        if nova.action and nova.action not in {"none", ""}:
            await session.send_command(nova.action)
        await session.set_state("speaking")
        await session.say(nova.reply, final=True)

    async def _fast_then_maybe_brain(
        self,
        session: RobotSession,
        text: str,
        plan: BehaviorPlan,
    ) -> tuple[str, str]:
        nova = await self.fast.complete(text, style=plan.speech_style)
        if nova.escalate:
            log.info("Fast model escalated to gpt-oss")
            thinking = nova.reply or "One sec, I'm thinking!"
            await session.send_model(self._brain_name(), "brain", transferring=True)
            await session.send_face("thinking", 0.7, 80, face="thinking_01")
            await session.send_chat("nova", thinking, "thinking", "thinking_01")
            await session.say(thinking, final=True)
            plan.route = "brain"
            await session.send_behavior(plan)
            answer = await self._speak_stream(
                session,
                self.gpt.stream(text, style=plan.speech_style, reasoning_level="medium"),
            )
            if answer:
                await session.send_chat("nova", answer, "focused", "focused_01")
            return answer, "brain"
        if not nova.reply:
            nova.reply = "Hmm?"
        await self._deliver_nova(session, nova)
        return nova.reply, "fast"

    async def _speak_stream(
        self,
        session: RobotSession,
        tokens: AsyncIterator[str],
        on_token=None,
        suppress_escalate: bool = False,
    ) -> str:
        await session.set_state("speaking")
        spoken: list[str] = []
        pending = ""

        async def wrapped(token: str) -> None:
            nonlocal pending
            pending += token
            if on_token:
                await on_token(token)

        async for phrase in stream_phrases(tokens, on_token=wrapped):
            if suppress_escalate and phrase.strip().upper() == ESCALATE_TOKEN:
                continue
            spoken.append(phrase)
            await session.say(phrase, final=False)

        final_text = " ".join(spoken).strip() or pending.strip()
        if suppress_escalate and final_text.upper() == ESCALATE_TOKEN:
            return ESCALATE_TOKEN
        if not spoken and pending.strip() and pending.strip().upper() != ESCALATE_TOKEN:
            await session.say(pending.strip(), final=True)
        elif spoken:
            await session.say("", final=True)
        return final_text
