# Deskbot Cloud API

Backend for **user accounts** and **Comfy LTX generation**. The phone app never holds the Comfy API key.

**Public base URL (planned):** `https://deskbot.inmomentservices.com`

## Architecture

```
Flutter app  --JWT-->  deskbot.inmomentservices.com
                           |-- /v1/auth/register|login
                           |-- /v1/me
                           |-- /v1/ltx/jobs  → Comfy Cloud (server-side key)
                           `-- returns RGB565 frames for BLE upload
```

## Local run

```powershell
cd D:\Projects\Deskbot\cloud
copy .env.example .env
# set JWT_SECRET + COMFY_API_KEY
pip install -r requirements.txt
# ffmpeg must be on PATH for frame extract
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Health: `GET http://127.0.0.1:8000/health`

## Deploy (Docker)

```bash
docker build -t deskbot-cloud .
docker run -d -p 8000:8000 \
  -e JWT_SECRET=... \
  -e COMFY_API_KEY=comfyui-... \
  -v deskbot-data:/app/data \
  deskbot-cloud
```

Point `deskbot.inmomentservices.com` (reverse proxy / TLS) at this container.

## Raspberry Pi deploy

On the Pi (64-bit Raspberry Pi OS):

```bash
# One-time: clone or pull
cd ~
git clone https://github.com/samsarastudio/Deskbot.git || (cd Deskbot && git pull)
cd Deskbot/cloud
cp .env.example .env
nano .env   # JWT_SECRET=...  COMFY_API_KEY=comfyui-...

# Docker (install docker.io first if needed)
chmod +x deploy-pi.sh
./deploy-pi.sh

# TLS — example Caddy (see deploy/caddy-snippet.example)
sudo apt install -y caddy
# add site block, then: sudo systemctl reload caddy
```

Update app only after DNS + TLS work:

```bash
curl -s https://deskbot.inmomentservices.com/health
```

Local dev app against Pi LAN:

```powershell
flutter run --dart-define=DESKBOT_API_BASE=http://192.168.x.x:8000
```

## API sketch

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| POST | `/v1/auth/register` | no | create account |
| POST | `/v1/auth/login` | no | JWT |
| GET/PATCH | `/v1/me` | yes | profile |
| POST | `/v1/ltx/jobs` | yes | queue LTX generation |
| GET | `/v1/ltx/jobs/{id}` | yes | status + `frames_b64` when done |

App polls job until `status` is `succeeded` or `failed`.
