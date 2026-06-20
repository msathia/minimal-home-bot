#!/usr/bin/env bash
set -euo pipefail

KEEP_MODEL="${1:-${OLLAMA_MODEL:-llama3.2:3b}}"

if ! command -v ollama >/dev/null 2>&1; then
  echo "ollama command not found."
  exit 1
fi

echo "Keeping Ollama model: ${KEEP_MODEL}"
ollama pull "$KEEP_MODEL"

echo "==> Stopping loaded models except ${KEEP_MODEL}"
while read -r model _; do
  [[ -z "${model:-}" || "$model" == "NAME" || "$model" == "$KEEP_MODEL" ]] && continue
  ollama stop "$model" >/dev/null 2>&1 || true
done < <(ollama ps)

echo "==> Removing installed models except ${KEEP_MODEL}"
while read -r model _; do
  [[ -z "${model:-}" || "$model" == "NAME" || "$model" == "$KEEP_MODEL" ]] && continue
  ollama rm "$model"
done < <(ollama list)

echo "==> Remaining Ollama models"
ollama list

echo "==> Ollama model directory size"
du -sh ~/.ollama/models 2>/dev/null || true
