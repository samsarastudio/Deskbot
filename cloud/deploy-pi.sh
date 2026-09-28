#!/usr/bin/env bash
# Deskbot Cloud on Raspberry Pi (64-bit OS recommended).
# Run on the Pi after cloning the repo and DNS points deskbot.inmomentservices.com here.

set -euo pipefail

REPO_DIR="${REPO_DIR:-$HOME/Deskbot}"
CLOUD_DIR="$REPO_DIR/cloud"
ENV_FILE="$CLOUD_DIR/.env"

echo "==> Deskbot cloud deploy (Pi)"
echo "    repo: $REPO_DIR"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Create $ENV_FILE from .env.example (JWT_SECRET + COMFY_API_KEY)"
  cp "$CLOUD_DIR/.env.example" "$ENV_FILE"
  echo "Edit $ENV_FILE then re-run this script."
  exit 1
fi

# Docker path (recommended)
if command -v docker >/dev/null 2>&1; then
  cd "$CLOUD_DIR"
  docker build -t deskbot-cloud:latest .
  docker stop deskbot-cloud 2>/dev/null || true
  docker rm deskbot-cloud 2>/dev/null || true
  mkdir -p "$CLOUD_DIR/data"
  docker run -d \
    --name deskbot-cloud \
    --restart unless-stopped \
    -p 127.0.0.1:8000:8000 \
    --env-file "$ENV_FILE" \
    -v "$CLOUD_DIR/data:/app/data" \
    deskbot-cloud:latest
  echo "API listening on http://127.0.0.1:8000 — put TLS reverse proxy in front."
  curl -sf http://127.0.0.1:8000/health | head -c 200 || true
  echo
  exit 0
fi

# Fallback: venv + uvicorn (needs ffmpeg on Pi)
sudo apt-get update
sudo apt-get install -y ffmpeg python3-venv python3-pip
cd "$CLOUD_DIR"
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
mkdir -p data
set -a
source "$ENV_FILE"
set +a
echo "Start manually: cd $CLOUD_DIR && source .venv/bin/activate && uvicorn app.main:app --host 127.0.0.1 --port 8000"
echo "Or install systemd unit from deploy/deskbot-cloud.service.example"
