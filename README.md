# Minimal Home Bot — Build on a Lean Machine

Build a **home-based Telegram AI bot** on a **minimal-footprint machine** — local Ollama inference, modular skills, and always-on systemd service. This blueprint uses **Xubuntu Minimal** to keep RAM and disk use low.

**Example deployment:** a 2017 Intel iMac (8 GB RAM / 1 TB HDD) dual-booting macOS Ventura (~250 GB) + Xubuntu Minimal (~750 GB). The steps below work on any small PC, laptop, or Mac with similar constraints.

> **Note — hardware is flexible.** The iMac specs above are my personal setup, not hard requirements. Any machine with a modest RAM footprint and a smaller disk works fine for this bot stack. What actually matters:
>
> | Resource | Minimum | Comfortable | What consumes it |
> |----------|---------|-------------|------------------|
> | **RAM** | 4 GB | 8 GB+ | Xubuntu Minimal idle ~600 MB; `llama3.2:3b` inference is the default and fits the 8 GB iMac target better than Qwen on CPU; the Telegram bot and yt-dlp skill add only tens of MB |
> | **Linux disk** | ~32 GB | 64 GB+ | Xubuntu Minimal ~8–15 GB; Ollama + `llama3.2:3b` model ~2 GB; headroom for logs and updates |
> | **Dual-boot disk** | ~128 GB total | 256 GB+ | macOS slice (~50–100 GB) + Linux slice (see above); partition sizes scale down — you do not need 1 TB |
>
> A smaller SSD, an older laptop, or a Linux-only install (no macOS slice) all fit this blueprint. Scale the model down further (e.g. `llama3.2:1b`) if RAM is tight.

See **[NETWORKING.md](NETWORKING.md)** for how your home machine reaches Telegram over the internet (long polling, NAT, and protocol flow).

## Repository Layout

```
.
├── ai_bot/
│   ├── ai_bot.py              # Telegram ↔ Ollama polling bot
│   └── requirements.txt       # Python dependencies
├── NETWORKING.md              # How local bot traffic reaches Telegram
├── nanobot/skills/
│   └── yt-recommender/
│       ├── SKILL.md           # Agent directive for video recommendations
│       └── scripts/
│           └── search_yt.py   # On-demand yt-dlp metadata worker
├── deploy/
│   ├── apt/nosnap.pref        # Blocks snapd re-install
│   └── systemd/aibot.service  # Systemd unit template
└── scripts/
    ├── imac-install.sh        # One-time service install wrapper
    ├── imac-refresh.sh        # Pull bot updates, update deps, restart service
    ├── ollama-prune-models.sh # Keep one Ollama model and remove the rest
    ├── post-install.sh        # Post-Xubuntu setup automation
    └── install-service.sh     # Deploy and enable systemd service
```

---

## Part 1: Cleaning and Disk Partitioning (macOS Side)

Before touching the Linux installer, partition inside **macOS Ventura**.

### Step 1: Disk Utility Breakdown

1. Open **Disk Utility**.
2. **View → Show All Devices**.
3. Select the main internal physical storage container (e.g. **APPLE HDD**).
4. Click **Partition**.

### Step 2: Slice the Volumes

1. Allocate **~250 GB** for macOS.
2. Click **+** to create a new zone:
   - **Name:** Linux Space (or generic)
   - **Format:** MS-DOS (FAT) or ExFAT (temporary divider)
   - **Size:** ~750 GB
3. Click **Apply** and wait for the resize to finish.
4. Select the new 750 GB slice → **Erase** → **Free Space** (unallocated). This leaves raw space for the Linux installer.

---

## Part 2: Installing Xubuntu Minimal

### Step 1: Boot the Live Installer

1. Shut down the machine.
2. Insert the flash drive. On Apple hardware, hold **Option (⌥)** while powering on; on PCs, use your firmware boot menu key.
3. Select the **EFI Boot** volume with your Linux image.
4. On the GRUB menu, choose **Try or Install Xubuntu**.

### Step 2: Installer Wizard

| Screen | Setting |
|--------|---------|
| Installation type | **Xubuntu Minimal** (~591 MB idle RAM vs ~771 MB full) |
| Third-party software | **Checked** (Intel graphics + Broadcom Wi-Fi) |
| Additional media formats | **Unchecked** |

### Step 3: Manual Partitioning ("Something Else")

Enable **Manual Installation**, then map:

| Partition | Action |
|-----------|--------|
| **sda1** (VFAT ~200 MB) | Leave **Format** unchecked. Mount: `/boot/efi` |
| **sda2** (APFS ~250 GB) | **Do not touch** — macOS volume |
| **free space** (~750 GB) | Create primary **Ext4**, mount `/`, **Format checked** |

**Boot loader:** `/dev/sda` (top-level drive, not sda1/sda3).

Complete username, password, and installation.

---

## Part 3: Post-Install Optimization

Clone this repo on the host machine, then run from the repo root:

```bash
git clone https://github.com/msathia/minimal-home-bot.git ~/minimal-home-bot
cd ~/minimal-home-bot
chmod +x scripts/*.sh
./scripts/post-install.sh
```

Or run steps manually:

### Snap Removal

```bash
snap list
sudo snap remove --purge snapd-desktop-integration
sudo snap remove --purge bare
sudo snap remove --purge core22
sudo snap remove --purge snapd

sudo systemctl stop snapd.service
sudo systemctl disable snapd.service
sudo systemctl mask snapd.service

sudo apt purge snapd -y
rm -rf ~/snap
sudo rm -rf /var/cache/snapd/

sudo cp deploy/apt/nosnap.pref /etc/apt/preferences.d/nosnap.pref
```

### Lightweight Browser

```bash
sudo apt update
sudo apt install midori -y
```

---

## Part 4: AI Pipeline

### Ollama

```bash
curl -fsSL https://ollama.com/install.sh | sh
systemctl status ollama
ollama pull llama3.2:3b
```

`llama3.2:3b` is the default model because it gives the 8 GB Intel iMac a more responsive CPU-only path than Qwen. Qwen models can produce better answers on stronger hardware, but `qwen3:4b` was too slow for this target machine. Use `llama3.2:3b`, not `llama3.1:3b`; Llama 3.1 starts at larger 8B-class models in Ollama.

The bot reads these optional environment settings:

```bash
export OLLAMA_MODEL=llama3.2:3b
export OLLAMA_NUM_CTX=4096
export OLLAMA_NUM_PREDICT=512
export OLLAMA_TIMEOUT=300
export OLLAMA_KEEP_ALIVE=10m
```

The service installer writes these values to `/etc/default/aibot`. `OLLAMA_NUM_CTX=4096` and `OLLAMA_NUM_PREDICT=512` keep latency and memory use conservative for the 8 GB iMac. `OLLAMA_TIMEOUT=300` gives the bot enough time for slow first-load model startup on older HDD systems, and `OLLAMA_KEEP_ALIVE=10m` keeps the model warm between nearby Telegram messages.

### Python Virtual Environment

```bash
pkill -f ai_bot.py || true
sudo apt install python3-venv python3-pip -y
cd ~/minimal-home-bot
python3 -m venv .venv
.venv/bin/pip install --upgrade -r ai_bot/requirements.txt
```

### Telegram Token

1. Message [@BotFather](https://t.me/BotFather) on Telegram to create a bot and get a token.
2. Export it:

```bash
export TELEGRAM_TOKEN="your_token_here"
```

Or copy `.env.example` to `.env` and fill in the token (`.env` is gitignored).

---

## Part 5: Nanobot Skills

Skills live inside this repo under `nanobot/skills/`. The systemd service points `NANOBOT_SKILLS_DIR` at that repo-local directory, so pulling this repo updates bot code and skill code together.

### yt-recommender

- **SKILL.md** — tells the agent how to use search results.
- **search_yt.py** — runs `yt-dlp` on demand (~50 MB RAM briefly).

Test the worker:

```bash
python3 ~/minimal-home-bot/nanobot/skills/yt-recommender/scripts/search_yt.py "machine learning tutorials"
```

The bot auto-invokes this skill when messages mention youtube, video, watch, or recommend.

### Optional External Worker

For private or project-specific automations, keep the worker outside this public repo and point the bot at it with `HOME_BOT_EXTERNAL_WORKER`.

The worker receives the message text:

```bash
python3 /path/to/private_worker.py --text "user message"
```

It should print JSON to stdout:

```json
{"handled": true, "replies": ["Done."]}
```

Return `{"handled": false}` when the worker should let the normal local model answer.

Configure it before installing the service:

```bash
export HOME_BOT_EXTERNAL_WORKER="/path/to/private_worker.py"
export HOME_BOT_EXTERNAL_TIMEOUT=120
```

The service installer writes those values to `/etc/default/aibot`.

If a private integration lives in another repo, such as `myLibrary`, reinstall that integration after reinstalling or resetting `aibot.service`. The public bot only provides the generic `HOME_BOT_EXTERNAL_WORKER` hook; the private repo owns its own worker path, sync command, and repo-specific environment values.

---

## Part 6: Systemd Service (Always-On)

From the repo root on the host machine:

```bash
./scripts/imac-install.sh sathia YOUR_TELEGRAM_TOKEN
```

Replace `sathia` with your Xubuntu username.

This creates `.venv`, installs Python dependencies, writes `/etc/default/aibot`, installs `aibot.service`, and creates these helper commands:

```bash
homebot-refresh   # pull minimal-home-bot, update deps, restart aibot
```

Future bot updates:

```bash
homebot-refresh
```

### Keep Only the Default Ollama Model

On the Xubuntu iMac:

```bash
cd ~/minimal-home-bot
git pull --ff-only
curl -fsSL https://ollama.com/install.sh | sh
ollama --version
ollama pull llama3.2:3b
homebot-refresh
```

If `homebot-refresh` is not installed yet, run the script directly:

```bash
./scripts/imac-refresh.sh
```

The refreshed bot defaults to `llama3.2:3b`. To remove every other local Ollama model and free model disk space:

```bash
./scripts/ollama-prune-models.sh llama3.2:3b
ollama list
du -sh ~/.ollama/models 2>/dev/null || true
```

To free memory after pruning models:

```bash
sudo systemctl restart ollama
sudo systemctl restart aibot
ollama ps
```

General safe disk cleanup:

```bash
sudo apt autoremove --purge -y
sudo apt clean
sudo journalctl --vacuum-time=7d
rm -rf ~/.cache/pip ~/.cache/thumbnails/*
df -h /
```

Manual restart:

```bash
sudo systemctl restart aibot
```

### Debugging

```bash
journalctl -u aibot -f
```

---

## Hardware Notes

- **RAM:** 4 GB minimum, 8 GB+ comfortable — use `llama3.2:3b` by default, or `llama3.2:1b` for tighter machines.
- **Storage:** HDD works but SSD is faster for model loads; minimal install reduces background I/O.
- **Wi-Fi (Apple hardware):** Enable third-party drivers during install for Broadcom Wi-Fi chips.

---

## License

Personal homelab project — adapt freely.
