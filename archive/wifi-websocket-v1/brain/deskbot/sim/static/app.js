const TOKEN = "deskbot-local-dev";
const DEVICE_ID = "deskbot-sim";

const logEl = document.getElementById("log");
const connEl = document.getElementById("conn");
const lcd = document.getElementById("lcd");
const lcdState = document.getElementById("lcdState");
const poseEl = document.getElementById("pose");
const routeEl = document.getElementById("route");
const styleEl = document.getElementById("style");
const robotEl = document.getElementById("robot");
const aiModelEl = document.getElementById("aiModel");
const aiCard = document.getElementById("aiCard");
const routeCard = document.getElementById("routeCard");
const xferBanner = document.getElementById("xferBanner");

let models = { fast: "qwen3.5:0.8b", brain: "gpt-oss:20b", behavior: "qwen3.5:0.8b" };

function setTransferring(on) {
  [aiModelEl, routeEl, aiCard, routeCard].forEach((el) => {
    if (el) el.classList.toggle("xfer", !!on);
  });
  if (xferBanner) xferBanner.classList.toggle("show", !!on);
}

function showModel(name, role, transferring) {
  if (aiModelEl) {
    aiModelEl.textContent = name || "—";
    aiModelEl.classList.toggle("big", role === "brain" && !transferring);
    aiModelEl.title = role ? `${role}: ${name}` : (name || "");
  }
  setTransferring(transferring);
  if (transferring && xferBanner) {
    xferBanner.textContent = `Transferring to ${models.brain || name}…`;
  }
}
const textEl = document.getElementById("text");
const clockEl = document.getElementById("clock");
const ampmEl = document.getElementById("ampm");
const lcdEmotion = document.getElementById("lcdEmotion");
const promptText = document.getElementById("promptText");
const smileyEl = document.getElementById("smiley");
const introEl = document.getElementById("intro");

function toLcdText(text) {
  const punct = {
    "\u2014": "-",
    "\u2013": "-",
    "\u2212": "-",
    "\u2018": "'",
    "\u2019": "'",
    "\u201c": '"',
    "\u201d": '"',
    "\u2026": "...",
    "\u00a0": " ",
  };
  const emoji = {
    "😊": "^_^", "🙂": "^_^", "😁": "^o^", "😄": ":D", "😃": ":D", "😀": ":D",
    "😅": "^_^", "😆": "^o^", "😂": "^o^", "🤣": "^o^", "😉": "^-_",
    "😍": "<3", "🥰": "<3", "😘": "<3", "🤗": "^_^", "🤩": "^v^", "😇": "^_^",
    "😎": "B)", "😜": "^o^", "🤔": "-_-", "😐": "-_-", "😑": "-_-", "😴": "-_-",
    "😢": "T_T", "😭": "T_T", "😞": "T_T", "😔": "T_T", "🥺": "T_T",
    "😮": "o_o", "😲": "O_O", "😯": "o_o", "😳": "o_o", "😡": ">_<", "😤": ">_<",
    "😬": "-_-", "🙄": "-_-", "❤️": "<3", "❤": "<3", "♥": "<3", "💕": "<3",
    "💖": "<3", "💗": "<3", "💙": "<3", "💜": "<3", "💛": "<3", "💚": "<3",
    "🤍": "<3", "🖤": "<3", "♥️": "<3", "🫶": "<3", "🎉": "^v^", "🥳": "^v^",
    "✨": "", "🔥": "", "👍": "", "🙏": "",
  };
  let out = String(text || "").replace(/\r\n/g, "\n").replace(/\r/g, "\n");
  for (const [src, dst] of Object.entries(punct)) out = out.split(src).join(dst);
  for (const [src, dst] of Object.entries(emoji)) out = out.split(src).join(dst ? ` ${dst} ` : " ");
  out = out.replace(/[^\n\t\x20-\x7E]/g, "");
  return out.replace(/[ \t]{2,}/g, " ").replace(/ *\n */g, "\n").trim();
}

function moodFromMessage(msg) {
  return (msg && (msg.emotion || msg.expression)) || "happy";
}

function setSmiley(emotion) {
  if (!smileyEl) return;
  smileyEl.dataset.mood = emotion || "happy";
}

let ws = null;
let pose = { yaw: 0, pitch: 0 };
let heartbeatTimer = null;
let blinkTimer = null;

function log(line) {
  const at = new Date().toLocaleTimeString();
  logEl.textContent = `[${at}] ${line}\n` + logEl.textContent;
}

function setConn(ok, detail) {
  connEl.className = "conn " + (ok ? "connected" : "disconnected");
  connEl.textContent = detail;
}

function speak(text) {
  if (!document.getElementById("voiceOut").checked || !text || !window.speechSynthesis) return;
  const utter = new SpeechSynthesisUtterance(text);
  utter.rate = 1.05;
  window.speechSynthesis.cancel();
  window.speechSynthesis.speak(utter);
}

function formatClock(date) {
  let hours = date.getHours();
  const minutes = String(date.getMinutes()).padStart(2, "0");
  const ampm = hours >= 12 ? "PM" : "AM";
  hours = hours % 12 || 12;
  return { hours: String(hours), minutes, ampm };
}

function tickClock() {
  const { hours, minutes, ampm } = formatClock(new Date());
  clockEl.innerHTML = `${hours}<span class="colon">:</span>${minutes}`;
  ampmEl.textContent = ampm;
}

function blinkOnce() {
  if (lcd.dataset.state === "sleep" || lcd.dataset.expression === "surprised" || lcd.classList.contains("heart-fx")) return;
  lcd.classList.add("blinking");
  const closeMs = lcd.dataset.expression === "sleepy" ? 260 : 150;
  setTimeout(() => lcd.classList.remove("blinking"), closeMs);
}

function scheduleBlink() {
  clearTimeout(blinkTimer);
  const sleepy = lcd.dataset.expression === "sleepy" || lcd.dataset.state === "sleep";
  const delay = sleepy
    ? 1600 + Math.random() * 1800
    : 2400 + Math.random() * 4200;
  blinkTimer = setTimeout(() => {
    blinkOnce();
    if (!sleepy && Math.random() < 0.14) {
      setTimeout(blinkOnce, 180);
    }
    scheduleBlink();
  }, delay);
}

let heartUntil = 0;
let heartRaf = 0;

function playHeartFx() {
  const now = Date.now();
  if (now < heartUntil - 500) return;
  heartUntil = now + 2400;
  lcd.classList.remove("heart-fx");
  void lcd.offsetWidth;
  lcd.classList.add("heart-fx");
  runHeartParticles();
  setTimeout(() => lcd.classList.remove("heart-fx"), 2400);
}

function runHeartParticles() {
  const canvas = document.getElementById("heartParticles");
  if (!canvas) return;
  const ctx = canvas.getContext("2d");
  const w = canvas.width;
  const h = canvas.height;
  const parts = [];
  const cx = w / 2;
  const cy = h * 0.48;
  const start = performance.now();
  cancelAnimationFrame(heartRaf);

  function spawn(burst) {
    const ang = -Math.PI / 2 + (Math.random() - 0.5) * 1.6;
    const spd = 70 + Math.random() * 140 + (burst ? 50 : 0);
    parts.push({
      x: cx + (Math.random() - 0.5) * 220,
      y: cy + (Math.random() - 0.5) * 70,
      vx: Math.cos(ang) * spd * 0.4,
      vy: Math.sin(ang) * spd,
      life: 0.5 + Math.random() * 0.7,
      age: 0,
      r: 2 + Math.random() * 4,
      kind: Math.floor(Math.random() * 3),
    });
  }
  for (let i = 0; i < 18; i++) spawn(true);

  function drawHeart(x, y, s, a) {
    ctx.save();
    ctx.translate(x, y);
    ctx.scale(s, s);
    ctx.globalAlpha = a;
    ctx.fillStyle = "#ff2d55";
    ctx.shadowColor = "#ff4d7a";
    ctx.shadowBlur = 4;
    ctx.beginPath();
    ctx.moveTo(0, 6);
    ctx.bezierCurveTo(-9, -2, -8, -10, 0, -6);
    ctx.bezierCurveTo(8, -10, 9, -2, 0, 6);
    ctx.fill();
    ctx.restore();
  }

  let last = start;
  function frame(ts) {
    const t = (ts - start) / 1000;
    const dt = Math.min(0.05, Math.max(0.008, (ts - last) / 1000));
    last = ts;
    if (t > 2.4) {
      ctx.clearRect(0, 0, w, h);
      return;
    }
    if (t > 0.06 && t < 1.6 && Math.random() < 0.7) spawn(false);
    ctx.clearRect(0, 0, w, h);
    for (let i = parts.length - 1; i >= 0; i--) {
      const p = parts[i];
      p.age += dt;
      p.vy += 70 * dt;
      p.vx *= 0.99;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      const fade = 1 - p.age / p.life;
      if (fade <= 0) {
        parts.splice(i, 1);
        continue;
      }
      if (p.kind === 1) {
        drawHeart(p.x, p.y, 0.35 + fade * 0.45, fade);
      } else if (p.kind === 2) {
        ctx.save();
        ctx.globalAlpha = fade;
        ctx.strokeStyle = "#ffd27a";
        ctx.shadowColor = "#ff7aa2";
        ctx.shadowBlur = 3;
        ctx.lineWidth = 2;
        ctx.beginPath();
        ctx.moveTo(p.x - 5, p.y);
        ctx.lineTo(p.x + 5, p.y);
        ctx.moveTo(p.x, p.y - 5);
        ctx.lineTo(p.x, p.y + 5);
        ctx.stroke();
        ctx.restore();
      } else {
        ctx.save();
        ctx.globalAlpha = fade;
        ctx.fillStyle = "#ffe6f0";
        ctx.shadowColor = "#ff4d7a";
        ctx.shadowBlur = 4;
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.r * fade, 0, Math.PI * 2);
        ctx.fill();
        ctx.restore();
      }
    }
    heartRaf = requestAnimationFrame(frame);
  }
  heartRaf = requestAnimationFrame(frame);
}

function startHeartbeat() {
  stopHeartbeat();
  heartbeatTimer = setInterval(() => {
    sendJson({ type: "heartbeat", ts_ms: Date.now() });
  }, 3000);
}

function stopHeartbeat() {
  if (heartbeatTimer) {
    clearInterval(heartbeatTimer);
    heartbeatTimer = null;
  }
}

function applyPoseTransform() {
  lcd.style.transform = `rotate(${pose.yaw * 0.35}deg) translateY(${-pose.pitch * 0.8}px)`;
}

function applyMessage(msg) {
  if (msg.type === "hello_ack") {
    setConn(true, `Connected · ${msg.session_id.slice(0, 8)}`);
    lcd.dataset.state = "idle";
    lcdState.textContent = "NOVA";
    if (msg.models) {
      models = { ...models, ...msg.models };
      showModel(models.fast, "fast", false);
    }
    startHeartbeat();
  }
  if (msg.type === "model") {
    showModel(msg.name, msg.role, !!msg.transferring);
    if (msg.transferring) {
      routeEl.textContent = "fast → brain";
    } else if (msg.role && msg.role !== "brain") {
      routeEl.textContent = msg.role;
    }
  }
  if (msg.type === "state") {
    lcd.dataset.state = msg.state;
    lcdState.textContent = msg.state === "offline" ? "OFFLINE" : msg.state === "sleep" ? "SLEEP" : "NOVA";
  }
  if (msg.type === "face" || msg.type === "behavior") {
    const emotion = moodFromMessage(msg);
    if (msg.emotion || msg.expression) {
      lcd.dataset.expression = emotion;
      if (lcdEmotion) lcdEmotion.textContent = String(emotion).toUpperCase();
      setSmiley(emotion);
    }
    if (msg.gaze) lcd.dataset.gaze = msg.gaze;
    if (msg.face && styleEl) styleEl.textContent = msg.face;
    else if (msg.speech_style && styleEl) styleEl.textContent = msg.speech_style;
  }
  if (msg.type === "chat") {
    const line = toLcdText(msg.text || "");
    if (msg.speaker === "user" || msg.speaker === "you") {
      if (!promptText || !promptText.dataset.nova) {
        if (promptText) promptText.textContent = line;
      }
    } else if (promptText) {
      promptText.textContent = line;
      promptText.dataset.nova = "1";
    }
    lcd.classList.add("has-chat");
    const emotion = msg.emotion || msg.expression || lcd.dataset.expression;
    if (emotion) {
      lcd.dataset.expression = emotion;
      if (lcdEmotion) lcdEmotion.textContent = String(emotion).toUpperCase();
      setSmiley(emotion);
    }
    if (msg.face && styleEl) styleEl.textContent = msg.face;
  }
  if (msg.type === "command" && msg.action === "name_intro") {
    lcd.classList.add("intro-fx", "has-chat");
    if (promptText) promptText.textContent = "That's me!";
    setSmiley("happy");
    setTimeout(() => lcd.classList.remove("intro-fx"), 2200);
  }
  if (msg.type === "fx" && msg.name === "heart") {
    playHeartFx();
  }
  if (msg.type === "face" && msg.expression === "love" && msg.face && String(msg.face).startsWith("love")) {
    /* heart eyes live on the face; full-screen heart is the Heart button FX */
  }
  if (msg.type === "motion") {
    if (msg.joint === "head_yaw") pose.yaw = msg.angle;
    if (msg.joint === "head_pitch") pose.pitch = msg.angle;
    if (poseEl) poseEl.textContent = `yaw ${pose.yaw} / pitch ${pose.pitch}`;
    applyPoseTransform();
  }
  if (msg.type === "turn") {
    const transferred = !!msg.transferred;
    routeEl.textContent = transferred ? "fast → brain" : (msg.route || "—");
    if (msg.model) {
      showModel(msg.model, msg.route === "brain" ? "brain" : msg.route, false);
    } else {
      setTransferring(false);
    }
  }
  if (msg.type === "devices") {
    const robot = (msg.devices || []).find((d) => !d.controller);
    if (robot) {
      robotEl.textContent = `${robot.device_id} · ${robot.state}`;
      robotEl.className = "on";
    } else {
      robotEl.textContent = "offline";
      robotEl.className = "off";
    }
  }
  if (msg.type === "say" && msg.text) {
    speak(msg.text);
  }
  if (msg.type === "audio_cancel" && window.speechSynthesis) {
    window.speechSynthesis.cancel();
  }
  if (msg.type !== "ping") {
    log(JSON.stringify(msg));
  }
}

function connect() {
  if (ws && (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING)) {
    ws.close();
  }
  stopHeartbeat();
  const url = `${location.protocol === "https:" ? "wss" : "ws"}://${location.host}/deskbot`;
  ws = new WebSocket(url);
  ws.onopen = () => {
    ws.send(JSON.stringify({
      type: "hello",
      device_id: DEVICE_ID,
      protocol: 1,
      token: TOKEN,
      capabilities: ["lcd", "sim", "speaker"],
    }));
  };
  ws.onmessage = (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.type === "ping") {
      sendJson({ type: "pong" });
      return;
    }
    applyMessage(msg);
  };
  ws.onclose = () => {
    stopHeartbeat();
    setConn(false, "Disconnected");
    lcd.dataset.state = "offline";
    lcdState.textContent = "OFFLINE";
    if (lcdEmotion) lcdEmotion.textContent = "OFFLINE";
  };
  ws.onerror = () => setConn(false, "Socket error");
}

function sendJson(obj) {
  if (!ws || ws.readyState !== WebSocket.OPEN) {
    log("not connected");
    return;
  }
  ws.send(JSON.stringify(obj));
}

document.getElementById("connectBtn").onclick = connect;
document.getElementById("talk").onsubmit = (ev) => {
  ev.preventDefault();
  const text = textEl.value.trim();
  if (!text) return;
  sendJson({ type: "user_text", text });
  routeEl.textContent = "…";
  setTransferring(false);
  textEl.value = "";
};
document.querySelectorAll("button[data-event]").forEach((btn) => {
  btn.onclick = () => sendJson({ type: "event", event: btn.dataset.event, zone: "head" });
});
document.querySelectorAll("button[data-control]").forEach((btn) => {
  btn.onclick = () => sendJson({ type: "control", action: btn.dataset.control });
});
document.querySelectorAll("button[data-expression]").forEach((btn) => {
  btn.onclick = () => sendJson({ type: "control", action: "expression", expression: btn.dataset.expression });
});

document.getElementById("micBtn").onclick = () => {
  const Speech = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (!Speech) {
    log("SpeechRecognition is not available in this browser");
    return;
  }
  const rec = new Speech();
  rec.lang = "en-US";
  rec.onresult = (ev) => {
    const text = ev.results[0][0].transcript;
    textEl.value = text;
    sendJson({ type: "user_text", text });
    routeEl.textContent = "…";
    setTransferring(false);
  };
  rec.start();
};

tickClock();
setInterval(tickClock, 1000);
scheduleBlink();
connect();
