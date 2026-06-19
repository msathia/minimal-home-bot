#!/usr/bin/env bash
set -euo pipefail

USERNAME="${1:-$(whoami)}"
TOKEN="${2:-${TELEGRAM_TOKEN:-}}"
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen3:4b}"
OLLAMA_NUM_CTX="${OLLAMA_NUM_CTX:-8192}"
OLLAMA_NUM_PREDICT="${OLLAMA_NUM_PREDICT:-1024}"

if [[ -z "$TOKEN" ]]; then
  echo "Usage: $0 [username] TELEGRAM_TOKEN"
  echo "Or set TELEGRAM_TOKEN in the environment."
  exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_HOME="$(getent passwd "$USERNAME" 2>/dev/null | cut -d: -f6 || true)"
if [[ -z "$TARGET_HOME" ]]; then
  TARGET_HOME="/home/${USERNAME}"
fi

VENV_DIR="${REPO_DIR}/.venv"
ENV_FILE="/etc/default/aibot"
SERVICE_FILE="/etc/systemd/system/aibot.service"
TMP_SERVICE=$(mktemp)
TMP_ENV=$(mktemp)
trap 'rm -f "$TMP_SERVICE" "$TMP_ENV"' EXIT

echo "==> Creating Python virtual environment in ${VENV_DIR}"
python3 -m venv "$VENV_DIR"
"${VENV_DIR}/bin/pip" install --upgrade pip
"${VENV_DIR}/bin/pip" install -r "${REPO_DIR}/ai_bot/requirements.txt"

echo "==> Writing service environment to ${ENV_FILE}"
{
  printf "TELEGRAM_TOKEN=%s\n" "$TOKEN"
  printf "OLLAMA_MODEL=%s\n" "$OLLAMA_MODEL"
  printf "OLLAMA_NUM_CTX=%s\n" "$OLLAMA_NUM_CTX"
  printf "OLLAMA_NUM_PREDICT=%s\n" "$OLLAMA_NUM_PREDICT"
  printf "NANOBOT_SKILLS_DIR=%s\n" "${REPO_DIR}/nanobot/skills"
  printf "HOME_BOT_EXTERNAL_WORKER=%s\n" "${HOME_BOT_EXTERNAL_WORKER:-}"
  printf "HOME_BOT_EXTERNAL_TIMEOUT=%s\n" "${HOME_BOT_EXTERNAL_TIMEOUT:-120}"
} > "$TMP_ENV"

if command -v ollama >/dev/null 2>&1; then
  echo "==> Pulling Ollama model ${OLLAMA_MODEL}"
  ollama pull "$OLLAMA_MODEL"
else
  echo "WARNING: ollama command not found; install Ollama and pull ${OLLAMA_MODEL} before starting the bot."
fi

echo "==> Rendering systemd unit for ${USERNAME}"
while IFS= read -r line; do
  line="${line//\/home\/sathia\/minimal-home-bot/$REPO_DIR}"
  line="${line//User=sathia/User=${USERNAME}}"
  printf "%s\n" "$line"
done < "${REPO_DIR}/deploy/systemd/aibot.service" > "$TMP_SERVICE"

sudo install -m 0600 "$TMP_ENV" "$ENV_FILE"
sudo install -m 0644 "$TMP_SERVICE" "$SERVICE_FILE"
sudo mkdir -p /usr/local/bin
sudo ln -sf "${REPO_DIR}/scripts/imac-refresh.sh" /usr/local/bin/homebot-refresh

sudo systemctl daemon-reload
sudo systemctl enable aibot.service
sudo systemctl restart aibot.service

echo "aibot.service installed and restarted."
echo "Refresh bot code later with: homebot-refresh"
echo "Monitor with: journalctl -u aibot -f"
