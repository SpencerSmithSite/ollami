# Ollami

Local-first macOS AI assistant. No telemetry, no cloud, no third-party AI.
Everything runs on your Mac via Ollama, faster-whisper, and SQLite.

Fork of [Omi](https://github.com/BasedHardware/omi) with all cloud dependencies removed.

---

## What it is

Ollami captures your screen and conversations, transcribes in real-time using faster-whisper on Apple Silicon, generates summaries and action items, and gives you an AI chat that remembers everything — powered entirely by a local Ollama model.

**Architecture**

```
macOS Swift App
      │
      ▼
Local Python FastAPI  (localhost:8080)
      │
      ├── faster-whisper    — speech-to-text (Apple Silicon optimised)
      ├── Ollama            — LLM for chat, summaries, action items
      ├── SQLite            — conversation + memory storage
      └── Chroma            — vector search (local embeddings via Ollama)
```

All data stays on your machine at `~/.ollami/`.

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| macOS | 14+ | — |
| Xcode | 15+ | App Store or `xcode-select --install` |
| Ollama | latest | `brew install ollama` |
| Python | 3.11+ | `brew install python@3.11` |

Pull a model before starting:

```bash
ollama pull llama3.2        # or any model you prefer
ollama pull nomic-embed-text  # for vector search (Phase 2)
```

---

## Setup

### 1. Clone

```bash
git clone https://github.com/YOUR_USERNAME/ollami.git
cd ollami
```

### 2. Build and run the macOS app

```bash
cd desktop
./run.sh
```

The app auto-generates a local token at `~/.ollami/token` on first launch.
Open **Settings → Ollami** to configure the Ollama URL, active model, and Whisper model size.

### 3. Local backend (Phase 2 — in progress)

The Python backend replaces the upstream cloud services. Not yet complete — see `TODO.md` Phase 2 tasks.

Once available:

```bash
cd backend
pip install -r requirements.txt
uvicorn main:app --port 8080
```

---

## Configuration

The **Settings → Ollami** panel exposes:

| Setting | Default | Description |
|---------|---------|-------------|
| Ollama URL | `http://localhost:11434` | Ollama server address |
| Active model | (live list from Ollama) | Model used for chat and summaries |
| Whisper model | `base` | `tiny` / `base` / `small` / `medium` |
| Backend URL | `http://localhost:8080` | Local Python FastAPI address |
| Plugins | — | Add webhook plugins by URL |

---

## What was removed from upstream Omi

- **Analytics** — Mixpanel, PostHog, Heap, Sentry, LangSmith, Datadog
- **Cloud auth** — Firebase OAuth replaced with a local UUID token
- **Cloud AI** — OpenAI, Anthropic, Deepgram, ElevenLabs replaced with local equivalents
- **Payments** — Stripe, subscription plans, upgrade prompts
- **Remote storage** — GCS replaced with `~/.ollami/data/`
- **Mobile app** — iOS/Android Flutter app (macOS-only fork)
- **Firmware** — Omi wearable and Omi Glasses firmware
- **Cloud infrastructure** — Modal serverless, Firestore, Pinecone, Typesense, Twilio

---

## Roadmap

See [`TODO.md`](TODO.md) for the full task list.

- **Phase 1** — Strip telemetry and cloud from Swift app ✅
- **Phase 2** — Local Python backend (SQLite, faster-whisper, Ollama) 🚧
- **Phase 3** — Plugin support UI
- **Phase 4** — Performance tuning, local TTS, Ollama agent

---

## License

MIT — same as upstream Omi.
