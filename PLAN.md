# Ollami — Build Plan

Fully local, fully private fork of Omi. No telemetry, no cloud, no third-party AI providers.
All AI runs via Ollama. All data stays on your Mac.

---

## Architecture Overview

### Original Omi Stack
```
macOS Swift App → Rust Backend (api.omi.me) → Python FastAPI (Modal) → Firebase / Deepgram / OpenAI / etc.
```

### Ollami Stack
```
macOS Swift App → Local Python FastAPI (localhost:8080) → Ollama + faster-whisper + SQLite + Chroma
```

**Key decisions:**
- **Rust backend** — collapsed into Python FastAPI (it was mostly Firestore CRUD + API proxying, trivially ported)
- **Auth-Python** — removed (single-user local app, no OAuth needed; auto-generate a local token on first run)
- **acp-bridge** — removed initially; Phase 4 will add a local Ollama-powered agent to replace it
- **Firebase** — replaced with SQLite via SQLAlchemy
- **Deepgram** — replaced with `faster-whisper` (Apple Silicon optimised, int8 quantisation)
- **Pinecone / Typesense** — replaced with Chroma (local, file-backed vector + full-text search)
- **All analytics** — deleted (Mixpanel, PostHog, Sentry, Heap, LangSmith, Datadog)
- **Stripe / Twilio / Hume / Perplexity** — deleted
- **Modal serverless** — removed; backend runs as a plain `uvicorn` process

---

## Directory Structure (Target)

```
Ollami/
├── PLAN.md                      ← this file
├── desktop/
│   └── Desktop/                 ← Swift/SwiftUI macOS app (modified)
├── backend/                     ← Python FastAPI (heavily modified)
│   ├── main.py
│   ├── database/                ← SQLite via SQLAlchemy (replaces Firestore)
│   ├── routers/                 ← trimmed to ~15 essential routers
│   ├── utils/
│   │   ├── llm/                 ← Ollama client (OpenAI-compatible)
│   │   ├── stt/                 ← faster-whisper WebSocket handler
│   │   ├── memory/              ← Chroma vector store
│   │   └── plugins/             ← webhook dispatcher
│   └── .env.local               ← local config (no secrets)
└── scripts/
    └── start.sh                 ← launches Ollama + backend + opens app
```

---

## Phase 1 — Strip Telemetry from Swift App

**Goal:** Remove all analytics, cloud auth, and external SDK dependencies from the macOS app.
**Estimated time:** 2–3 days

### 1a. Files to DELETE entirely
| File | Reason |
|------|--------|
| `desktop/Desktop/Sources/MixpanelManager.swift` | Mixpanel analytics |
| `desktop/Desktop/Sources/PostHogManager.swift` | PostHog analytics |
| `desktop/Desktop/Sources/HeapManager.swift` | Heap analytics |
| `desktop/Desktop/Sources/AnalyticsManager.swift` | Unified telemetry dispatcher (1128 lines) |

### 1b. Package.swift — Remove dependencies
Remove these SPM packages entirely:
- `firebase-ios-sdk` (FirebaseCore, FirebaseAuth)
- `mixpanel-swift`
- `posthog-ios`
- `sentry-cocoa`
- `heap-swift-core-sdk`

Keep: GRDB, swift-markdown-ui, onnxruntime, Sparkle (disabled but kept for later)

### 1c. Files to modify — remove Sentry calls
| File | Lines to remove |
|------|----------------|
| `OmiApp.swift` | Sentry init (lines 290–340), heartbeat timer (513–521), Firebase init (342–348) |
| `Logger.swift` | All `SentrySDK.*` calls (lines 126, 141, 158–181) |
| `AuthService.swift` | Sentry user context (345, 462, 1056); Firebase imports; entire OAuth flow |
| `ResourceMonitor.swift` | All `SentrySDK.*` calls (lines 99–328) |
| `FeedbackView.swift` | `SentrySDK.capture(feedback:)` (lines 142–160) — replace with local log file write |
| `Rewind/Core/RewindStorage.swift` | `SentrySDK.addBreadcrumb()` line 274 |
| `Rewind/Core/VideoChunkEncoder.swift` | `SentrySDK.addBreadcrumb()` lines 301, 412, 580 |
| `Rewind/Core/RewindOCRService.swift` | `SentrySDK.configureScope()` line 159 |
| `ProactiveAssistants/Assistants/Insight/InsightStorage.swift` | `FirebaseApp.app()` guard (191–192) |

### 1d. APIClient.swift — point to localhost
- Change base URL from `https://api.omi.me/` → `http://localhost:8080/`
- Make it configurable via `UserDefaults` / settings panel
- Remove auth header injection that uses Firebase tokens

### 1e. AuthService.swift — replace with local auth
- Remove entire Firebase auth flow
- On first launch: generate a UUID local user token, store in Keychain
- Send that token as `Authorization: Bearer <local-token>` to local backend
- Backend validates it trivially (single-user mode)

### 1f. UI cleanup — remove cloud-only links
| File | Lines | Action |
|------|-------|--------|
| `SettingsPage.swift` | 1727, 5327, 5328, 5345, 5455 | Remove pricing/omi.me links |
| `SidebarView.swift` | 551, 925 | Remove omi.me / affiliate links |
| `ChatPage.swift` | 190, 210 | Remove pricing upsell |
| `ConversationRowView.swift` | 146, 154 | Remove cloud share link |
| `AppsPage.swift` | 411 | Remove docs.omi.me link |
| `AppBuild.swift` | 8 | Remove Sparkle appcast URL |
| `ChatLabView.swift` | 431, 463 | Remove direct Anthropic API calls |

### 1g. Add Ollami settings panel
New SwiftUI settings view with:
- Ollama base URL (default: `http://localhost:11434`)
- Active Ollama model picker (fetched from `/api/tags`)
- Whisper model size selector (tiny / base / small / medium)
- Backend URL (default: `http://localhost:8080`)
- Plugin manager (add/remove webhook plugins by URL)

---

## Phase 2 — Local Python Backend

**Goal:** A fully working FastAPI backend with zero network calls. Runs locally via `uvicorn`.
**Estimated time:** 2 weeks

### 2a. Database — SQLite via SQLAlchemy (replaces Firestore)

New file: `backend/database/models.py` — SQLAlchemy ORM models:
```
User           (id, name, created_at, settings_json)
Conversation   (id, user_id, created_at, title, transcript, summary, source)
Segment        (id, conversation_id, speaker, text, start_time, end_time)
Memory         (id, user_id, content, embedding_id, created_at)
ChatSession    (id, user_id, created_at, title)
Message        (id, session_id, role, content, created_at)
ActionItem     (id, conversation_id, content, completed, created_at)
Plugin         (id, name, trigger, webhook_url, enabled)
```

Migration strategy: all `database/*.py` files that import Firestore get rewritten to use SQLAlchemy sessions. The function signatures stay the same — only the internals change. This isolates the blast radius.

### 2b. STT — faster-whisper (replaces Deepgram)

`backend/utils/stt/local_whisper.py`:
- Load `faster-whisper` model on startup (configurable size: tiny/base/small/medium)
- Expose the same WebSocket interface as the current Deepgram handler
- Accept raw PCM16 audio chunks via WebSocket
- Buffer → VAD (via `silero-vad`) → transcribe → stream word-level results back
- Speaker diarisation via `pyannote.audio` (already in requirements.txt — keep it)
- `WHISPER_MODEL_SIZE` env var, default `small`

Interface (unchanged from Swift app's perspective):
```
WS /v1/listen  →  { text, speaker, is_final, start, end }
```

### 2c. LLM — Ollama (replaces OpenAI / Anthropic / Gemini)

`backend/utils/llm/clients.py` — stripped to:
```python
from openai import AsyncOpenAI

ollama = AsyncOpenAI(
    base_url=os.getenv("OLLAMA_BASE_URL", "http://localhost:11434/v1"),
    api_key="ollama",  # required by SDK but unused
)
MODEL = os.getenv("OLLAMA_MODEL", "llama3.2")
```

Ollama's API is OpenAI-compatible, so every existing `openai`-style call works with a base URL swap.
All `langchain` / `langgraph` wrappers removed — replaced with direct async calls.

Tasks using different model tiers (mini / medium / large) will all use the same Ollama instance but with configurable model names:
- `OLLAMA_MODEL_FAST` (default: `llama3.2:3b`) — summaries, titles, action items
- `OLLAMA_MODEL_QUALITY` (default: `qwen2.5:7b`) — chat, memory extraction

### 2d. Vector search — Chroma (replaces Pinecone + Typesense)

`backend/utils/memory/vector_store.py`:
- Chroma client pointed at `~/.ollami/chroma/`
- Embeddings via Ollama (`nomic-embed-text` model — fast, local)
- Collections: `memories`, `conversations`, `screen_activity`
- Full-text search on conversation titles via SQLite FTS5 (replaces Typesense)

### 2e. File storage — local filesystem (replaces GCS)

`backend/utils/storage.py` — new implementation:
- Base path: `~/.ollami/data/`
- Subdirs: `audio/`, `profiles/`, `screenshots/`, `exports/`
- All GCS upload/download calls → local file read/write
- No signed URLs — direct file path access

### 2f. Auth — local single-user token

`backend/routers/auth.py` — stripped to:
- No OAuth, no Firebase
- On first run: backend generates and stores a UUID token in `~/.ollami/token`
- All routes validate `Authorization: Bearer <token>` against that file
- Single middleware function, ~20 lines

### 2g. Routers to KEEP (trimmed from 42 → ~15)

| Router | Keep? | Notes |
|--------|-------|-------|
| `transcribe.py` | ✅ | WebSocket STT — rewritten for faster-whisper |
| `conversations.py` | ✅ | Core CRUD — rewritten for SQLite |
| `chat.py` | ✅ | LLM chat — rewritten for Ollama |
| `chat_sessions.py` | ✅ | Session management |
| `memories.py` | ✅ | Memory CRUD + Chroma |
| `users.py` | ✅ | Trimmed to single-user profile |
| `action_items.py` | ✅ | Task extraction |
| `plugins.py` | ✅ | Plugin webhook dispatcher |
| `apps.py` | ✅ | Plugin registry (local config) |
| `updates.py` | ✅ | Local version check |
| `speech_profile.py` | ✅ | Speaker voice profiles (local files) |
| `knowledge_graph.py` | ✅ | Local knowledge graph |
| `auth.py` | ✅ | Local token auth only |
| `other.py` | ✅ | Health check, misc |
| `sync.py` | ⚠️ | Keep for local export only |

| Router | Delete? | Reason |
|--------|---------|--------|
| `payment.py` | ✅ DELETE | Stripe |
| `phone_calls.py` | ✅ DELETE | Twilio |
| `agents.py` | ⚠️ LATER | Agent VM — rewrite in Phase 4 |
| `oauth.py` | ✅ DELETE | Firebase OAuth |
| `custom_auth.py` | ✅ DELETE | Firebase |
| `fair_use_admin.py` | ✅ DELETE | Subscription quotas |
| `metrics.py` | ✅ DELETE | Telemetry |
| `scores.py` | ✅ DELETE | Telemetry |
| `trends.py` | ✅ DELETE | Telemetry |
| `wrapped.py` | ✅ DELETE | Cloud year-in-review |
| `integrations.py` | ⚠️ LATER | Keep for Phase 3 plugin work |
| `firmware.py` | ✅ DELETE | Wearable device OTA |
| `announcements.py` | ✅ DELETE | Cloud push notifications |

### 2h. Plugin webhook dispatcher

`backend/utils/plugins/dispatcher.py`:
```python
async def fire_event(event: str, payload: dict, db: Session):
    plugins = db.query(Plugin).filter_by(trigger=event, enabled=True).all()
    for plugin in plugins:
        async with httpx.AsyncClient() as client:
            await client.post(plugin.webhook_url, json=payload, timeout=10)
```

Lifecycle events fired:
- `on_conversation_end` — transcript, summary, action items
- `on_memory_created` — memory content + metadata
- `on_chat_message` — for prompt-injection plugins (response merged into system prompt)

Plugins defined in `~/.ollami/plugins/` as JSON files or managed via the settings UI.

### 2i. requirements.txt — final local-only set

**Keep:**
- fastapi, uvicorn, starlette, pydantic
- sqlalchemy (ORM)
- httpx (async HTTP for plugin webhooks)
- websockets
- faster-whisper
- silero-vad (VAD)
- pyannote.audio (diarisation)
- chromadb (vector store)
- openai (SDK — used for Ollama OpenAI-compat API)
- python-dotenv
- cryptography (local token generation)

**Delete everything else** (~180 packages gone)

### 2j. New environment config

`backend/.env.local`:
```env
OLLAMA_BASE_URL=http://localhost:11434/v1
OLLAMA_MODEL_FAST=llama3.2:3b
OLLAMA_MODEL_QUALITY=qwen2.5:7b
WHISPER_MODEL_SIZE=small
DB_PATH=~/.ollami/ollami.db
CHROMA_PATH=~/.ollami/chroma
DATA_PATH=~/.ollami/data
LOCAL_TOKEN_PATH=~/.ollami/token
```

---

## Phase 3 — Plugin Support

**Goal:** Users can add webhook plugins (Omi-compatible protocol or custom).
**Estimated time:** 2–3 days

- Plugin CRUD API: `GET/POST/DELETE /v1/plugins`
- Plugin config stored in SQLite `Plugin` table
- Settings UI panel in Swift app: add plugin by URL, select trigger events, enable/disable
- On `on_conversation_end`: fire all enabled plugins with:
  ```json
  {
    "conversation_id": "...",
    "transcript": "...",
    "summary": "...",
    "action_items": [...],
    "memories": [...]
  }
  ```
- Plugins that respond with `{"system_prompt": "..."}` get that injected into the next chat context
- Compatible with existing Omi plugin webhook contract — any self-hosted Omi plugin works

**Note on cloud plugins (Notion, Linear, Slack, etc.):** These call external APIs at the user's discretion. Ollami doesn't block them — they're just webhook endpoints. Users understand they're sending data out.

---

## Phase 4 — Performance & Local Agent (later)

- Whisper model benchmarking on Apple Silicon (tiny vs small vs medium latency/accuracy)
- Ollama model benchmarking for each task (qwen2.5 vs llama3.2 vs mistral vs gemma3)
- Replace `acp-bridge` with a local Ollama tool-calling agent (LLM with tools)
- Local TTS (replace ElevenLabs) — Kokoro-TTS or piper-tts for voice responses
- Export/import conversations to JSON
- `start.sh` launcher: checks Ollama running → starts backend → opens app

---

## What We Are Not Building

- iOS / Android app
- Web admin panel
- Wearable device support (omiGlass, BLE)
- Multi-user support
- Subscription / payment system
- Cloud sync of any kind

---

## Build Order

1. **[Phase 1]** Strip Swift app — delete analytics files, remove SPM packages, stub auth, patch APIClient.swift
2. **[Phase 2a]** SQLite schema + SQLAlchemy models
3. **[Phase 2b]** faster-whisper STT WebSocket handler
4. **[Phase 2c]** Ollama LLM client + rewire all chat/memory routes
5. **[Phase 2d]** Chroma vector store + local embeddings
6. **[Phase 2e]** Local file storage
7. **[Phase 2f]** Single-user auth
8. **[Phase 2g]** Trim routers to the 15 keepers, delete the rest
9. **[Phase 2h]** Plugin dispatcher
10. **[Phase 3]** Plugin UI in Swift settings panel
11. **[Phase 4]** Performance tuning, local agent, TTS, launcher script
