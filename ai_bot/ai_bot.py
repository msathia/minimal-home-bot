import json
import logging
import os
import subprocess
import sys
from pathlib import Path

from telegram import Update
from telegram.ext import ApplicationBuilder, MessageHandler, filters, ContextTypes
import ollama

logging.basicConfig(
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    level=logging.INFO,
)

TOKEN = os.environ.get("TELEGRAM_TOKEN", "YOUR_TELEGRAM_TOKEN_HERE")
REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SKILLS_DIR = REPO_ROOT / "nanobot" / "skills"
LEGACY_SKILLS_DIR = Path.home() / "nanobot" / "skills"
SKILLS_DIR = Path(os.environ.get("NANOBOT_SKILLS_DIR", DEFAULT_SKILLS_DIR)).expanduser()
if not SKILLS_DIR.exists() and LEGACY_SKILLS_DIR.exists():
    SKILLS_DIR = LEGACY_SKILLS_DIR

SKILL_SEARCH_SCRIPT = SKILLS_DIR / "yt-recommender/scripts/search_yt.py"
EXTERNAL_WORKER_PATH = os.environ.get("HOME_BOT_EXTERNAL_WORKER", "").strip()
EXTERNAL_WORKER_SCRIPT = Path(EXTERNAL_WORKER_PATH).expanduser() if EXTERNAL_WORKER_PATH else None
EXTERNAL_WORKER_TIMEOUT = int(os.environ.get("HOME_BOT_EXTERNAL_TIMEOUT", "120"))
TELEGRAM_MESSAGE_SOFT_LIMIT = 3500


def chunk_text(value):
    text = str(value)
    if len(text) <= TELEGRAM_MESSAGE_SOFT_LIMIT:
        return [text]
    chunks = []
    current = ""
    for line in text.splitlines() or [text]:
        candidate = f"{current}\n{line}" if current else line
        if len(candidate) > TELEGRAM_MESSAGE_SOFT_LIMIT and current:
            chunks.append(current)
            current = line
        else:
            current = candidate
    if current:
        chunks.append(current)
    return chunks


def worker_replies(payload):
    replies = payload.get("replies")
    if isinstance(replies, str):
        replies = [replies]
    elif not isinstance(replies, list):
        reply = payload.get("reply") or payload.get("message") or payload.get("error")
        replies = [reply] if reply else ["External worker handled the request."]

    chunks = []
    for reply in replies:
        chunks.extend(chunk_text(reply))
    return chunks


async def maybe_handle_external_worker(user_text, update):
    if not EXTERNAL_WORKER_SCRIPT or not EXTERNAL_WORKER_SCRIPT.exists():
        return False

    try:
        result = subprocess.run(
            [sys.executable, str(EXTERNAL_WORKER_SCRIPT), "--text", user_text],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=EXTERNAL_WORKER_TIMEOUT,
        )
        payload = json.loads(result.stdout)
        if not payload.get("handled"):
            return False

        for reply in worker_replies(payload):
            await update.message.reply_text(reply)
        return True
    except (json.JSONDecodeError, subprocess.TimeoutExpired) as exc:
        logging.warning("External worker failed: %s", exc)
        await update.message.reply_text("Configured external worker failed before it could finish.")
        return True


async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_text = update.message.text
    logging.info("Incoming task request parsed: %s", user_text)

    system_prompt = (
        "You are a helpful AI assistant running locally on a minimal-footprint home machine "
        "using Xubuntu Minimal. You are efficient, concise, and aware of "
        "your hardware limitations. Your creator is Sathia."
    )

    messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": user_text},
    ]

    if await maybe_handle_external_worker(user_text, update):
        return

    # Invoke yt-recommender skill when the user asks for video suggestions.
    if SKILL_SEARCH_SCRIPT.exists() and any(
        kw in user_text.lower() for kw in ("youtube", "video", "watch", "recommend")
    ):
        try:
            result = subprocess.check_output(
                ["python3", str(SKILL_SEARCH_SCRIPT), user_text],
                stderr=subprocess.DEVNULL,
                text=True,
            )
            messages.insert(
                1,
                {
                    "role": "system",
                    "content": (
                        "The yt-recommender skill returned these candidate videos. "
                        "Select the best educational options and reply with titles and URLs:\n"
                        f"{result}"
                    ),
                },
            )
        except subprocess.CalledProcessError as exc:
            logging.warning("yt-recommender skill failed: %s", exc)

    try:
        response = ollama.chat(
            model="llama3.2:3b",
            messages=messages,
        )
        await update.message.reply_text(response["message"]["content"])
    except Exception as exc:
        logging.error("Inference processing failure occurred: %s", exc)
        await update.message.reply_text(
            "Engine error occurred during internal computing pass."
        )


if __name__ == "__main__":
    app = ApplicationBuilder().token(TOKEN).build()
    app.add_handler(MessageHandler(filters.TEXT & (~filters.COMMAND), handle_message))
    print("Script connected and listening via polling interface loops...")
    app.run_polling()
