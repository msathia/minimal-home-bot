#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_PATH" ]]; do
  SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
  SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
  [[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="${SCRIPT_DIR}/${SCRIPT_PATH}"
done
REPO_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")/.." && pwd)"
LOCK_FILE="/tmp/homebot-refresh-${USER:-user}.lock"
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen3:4b}"

mkdir -p "$(dirname "$LOCK_FILE")"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "Another homebot refresh is already running."
  exit 75
fi

if [[ -n "$(git -C "$REPO_DIR" status --porcelain)" ]]; then
  echo "minimal-home-bot has uncommitted changes; refusing to pull."
  git -C "$REPO_DIR" status --short
  exit 1
fi

branch="$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD)"
upstream="$(git -C "$REPO_DIR" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
if [[ -z "$upstream" ]]; then
  upstream="origin/${branch}"
fi

git -C "$REPO_DIR" fetch origin
read -r ahead behind < <(git -C "$REPO_DIR" rev-list --left-right --count "HEAD...${upstream}")

if (( ahead > 0 && behind > 0 )); then
  echo "minimal-home-bot has diverged from ${upstream}; resolve manually."
  exit 1
elif (( ahead > 0 )); then
  echo "minimal-home-bot has local commits not on ${upstream}; refusing to deploy."
  exit 1
elif (( behind > 0 )); then
  git -C "$REPO_DIR" pull --ff-only
else
  echo "minimal-home-bot already up to date."
fi

python3 -m venv "${REPO_DIR}/.venv"
"${REPO_DIR}/.venv/bin/pip" install -r "${REPO_DIR}/ai_bot/requirements.txt"

if command -v ollama >/dev/null 2>&1; then
  if ollama show "$OLLAMA_MODEL" >/dev/null 2>&1; then
    echo "Ollama model ${OLLAMA_MODEL} already installed."
  else
    ollama pull "$OLLAMA_MODEL"
  fi
else
  echo "WARNING: ollama command not found; install Ollama and pull ${OLLAMA_MODEL} before using the bot."
fi

sudo systemctl restart aibot.service
systemctl is-active aibot.service
echo "aibot.service restarted. Monitor with: journalctl -u aibot -f"
