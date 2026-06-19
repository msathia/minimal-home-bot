#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Removing Snap packages and blocking re-install..."
if command -v snap >/dev/null 2>&1; then
  snap list 2>/dev/null || true
  for pkg in snapd-desktop-integration bare core22 snapd; do
    sudo snap remove --purge "$pkg" 2>/dev/null || true
  done
fi

sudo systemctl stop snapd.service 2>/dev/null || true
sudo systemctl disable snapd.service 2>/dev/null || true
sudo systemctl mask snapd.service 2>/dev/null || true
sudo apt purge snapd -y 2>/dev/null || true
rm -rf ~/snap
sudo rm -rf /var/cache/snapd/

sudo mkdir -p /etc/apt/preferences.d
sudo cp deploy/apt/nosnap.pref /etc/apt/preferences.d/nosnap.pref

echo "==> Installing lightweight browser..."
sudo apt update
sudo apt install -y midori python3-venv python3-pip git

echo "==> Installing Ollama..."
curl -fsSL https://ollama.com/install.sh | sh

echo "==> Setting up repo-local AI bot virtual environment..."
cd "$REPO_DIR"
python3 -m venv .venv
"${REPO_DIR}/.venv/bin/pip" install -r "${REPO_DIR}/ai_bot/requirements.txt"

echo "==> Pulling default Ollama model..."
ollama pull llama3.2:3b

echo "Post-install complete. Run scripts/imac-install.sh with your username and Telegram token to install the service."
