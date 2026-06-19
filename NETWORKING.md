# Networking — How Your Home Machine Talks to Telegram

This document explains how a bot running on a **minimal home machine** can read Telegram messages and reply, even though the device sits behind a router with a private IP address.

The key idea: **your host never becomes a public server**. It makes **outbound** HTTPS calls to Telegram's cloud, pulls new messages, runs AI locally, and sends replies back out. No port forwarding required.

---

## The Big Picture

```text
Your phone (Telegram app)
        │
        │  MTProto / mobile data or Wi‑Fi
        ▼
Telegram Cloud (their servers worldwide)
        ▲
        │  HTTPS (Bot API) — outbound from your host
        │
   Home router (NAT)
        │
        ▼
   Home machine (Xubuntu)
   ├── ai_bot.py  ──polls──► api.telegram.org
   ├── Ollama     ──local──► 127.0.0.1:11434  (no internet)
   └── yt-dlp     ──outbound► youtube.com     (only when skill runs)
```

There are three separate network paths:

1. **You ↔ Telegram** — normal Telegram chat (Telegram's infrastructure).
2. **Host ↔ Telegram** — the bot's control channel (HTTPS long polling).
3. **Host ↔ Ollama** — entirely on the machine (loopback, no internet).

---

## What Happens When You Send a Message

### Step 1: You message the bot on Telegram

You open Telegram on your phone and send text to your bot (e.g. `@YourBotName`).

```text
Phone → Telegram servers (encrypted MTProto)
```

Telegram stores that message on **their** servers and associates it with your bot (created via [@BotFather](https://t.me/BotFather)).

Your home machine is **not involved yet**.

---

### Step 2: Your host asks Telegram "anything new?" (long polling)

The bot uses long polling via `app.run_polling()` in `ai_bot/ai_bot.py`:

```python
app.run_polling()
```

**Long polling** means:

- The host repeatedly makes **outbound HTTPS** requests to Telegram's Bot API:
  - `https://api.telegram.org/bot<TOKEN>/getUpdates`
- The request says: "Give me messages newer than update ID X."
- Telegram **holds the connection open** for a few seconds waiting for new messages.
- When you send a message, Telegram returns it in the HTTP response.
- The script parses the JSON and calls `handle_message()`.

**Important:** the host initiates every connection. Telegram never connects *into* your home network.

---

### Step 3: AI runs locally (no cloud inference)

Once a message arrives, processing stays on the host:

```text
ai_bot.py  ──HTTP──► 127.0.0.1:11434  (Ollama daemon)
                ◄── response ──
```

| Property | Value |
|----------|-------|
| Protocol | HTTP on localhost |
| Port forwarding | Not needed |
| Cloud AI APIs | Not used (unless you change the code) |
| Model weights | Stored on disk; inference uses local RAM/CPU |

If the YouTube skill triggers, `yt-dlp` makes a **separate outbound HTTPS** request to YouTube to fetch titles and video IDs. That is optional and on-demand only.

---

### Step 4: Bot sends the reply back out

After Ollama returns text, the bot calls Telegram's API again:

```text
POST https://api.telegram.org/bot<TOKEN>/sendMessage
```

Telegram delivers that to your phone through the normal Telegram app path.

---

## Why This Works Behind a Home Router (NAT)

Most home networks look like this:

```text
Internet
   │
   ▼
[Router]  public IP: 203.0.113.42
   │
   ├── Host:     192.168.1.50  (private)
   ├── Phone:    192.168.1.23  (private)
   └── ...
```

NAT (Network Address Translation) behavior:

| Direction | Works? | Why |
|-----------|--------|-----|
| **Outbound** (host → internet) | Yes | Router rewrites source IP and tracks the session |
| **Inbound** (internet → host) | No (by default) | No one on the internet knows your private `192.168.x.x` |

Your bot only needs **outbound HTTPS (TCP port 443)**. Home routers allow that by default.

You do **not** need:

- A public IP on the host
- Port forwarding (80, 443, etc. to the host)
- Dynamic DNS
- A reverse proxy or tunnel (ngrok, Cloudflare Tunnel, etc.)

Polling is the home-server pattern: **your machine calls the cloud**, not the other way around.

---

## Protocol Stack (Layer by Layer)

### When the bot polls Telegram

```text
Application:  Telegram Bot API (JSON over HTTPS)
Transport:    TCP
Network:      IP (routed through your router via NAT)
Link:         Wi‑Fi or Ethernet on the host
```

### When the bot talks to Ollama

```text
Application:  Ollama REST API (JSON)
Transport:    TCP
Network:      127.0.0.1 (loopback — never leaves the machine)
```

### When yt-dlp runs (YouTube skill)

```text
Application:  HTTPS to YouTube
Transport:    TCP 443
Network:      Outbound through NAT (same as browser traffic)
```

---

## What Must Be Working on the Host

### For Telegram messaging

1. **Internet access** — DNS resolution + outbound TCP 443
2. **Valid bot token** — authenticates your host machine to Telegram's API
3. **`aibot.service` running** — keeps polling after reboot

### For AI replies

4. **`ollama.service` running** — local inference daemon
5. **Model pulled** — e.g. `ollama pull llama3.2:3b`

The systemd unit declares startup order:

```ini
After=network.target ollama.service
```

Networking and Ollama come up first; then the bot starts.

---

## Long Polling vs Webhooks

Telegram supports two delivery modes:

| Mode | How it works | Home machine fit |
|------|----------------|---------------|
| **Long polling** (this project) | Host pulls updates from Telegram | Ideal — outbound HTTPS only |
| **Webhook** | Telegram POSTs updates to your public URL | Requires public HTTPS endpoint + open port or tunnel |

This project uses **long polling** (`app.run_polling()`). Webhooks would require exposing the host to the internet, which is harder to set up and less appropriate for a home machine.

---

## Security Model

The **bot token** is the secret credential. Anyone who possesses it can control your bot through Telegram's API.

Because the host only makes **outbound** calls to Telegram:

- Nothing listens on a public port for Telegram to connect to
- The token does not need to be exposed on your local network
- Store it in the systemd unit or an environment variable — never commit it to git

See `.env.example` and `.gitignore` in the repo root for the recommended pattern.

---

## End-to-End Flow (One Message)

```text
1. You: "What's a good Python tutorial?"
      → Telegram cloud stores it

2. Host: GET/POST api.telegram.org/getUpdates (long poll)
      ← Telegram returns your message JSON

3. Host: POST 127.0.0.1:11434/api/chat (Ollama)
      ← model generates answer locally

4. Host: POST api.telegram.org/sendMessage
      → Telegram cloud

5. Your phone: notification + bot reply appears
```

**Public anchor on the public internet:** Telegram Bot API, and optionally YouTube (via yt-dlp).

**Parts stay entirely local:** Ollama inference and model weights on the host.

---

## Related Files

| File | Role |
|------|------|
| `ai_bot/ai_bot.py` | Telegram long polling + Ollama calls |
| `deploy/systemd/aibot.service` | Keeps the bot running after reboot |
| `README.md` | Full install and setup blueprint |
