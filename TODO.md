# Ollami TODO

Local-first, private fork of Omi. No telemetry, no cloud, no third-party AI.
Everything runs on your Mac via Ollama + faster-whisper + SQLite.

See `PLAN.md` for full architecture details.

---

## Phase 1 — Strip the Swift Desktop App

### Completed ✅

- [x] **1a** — Delete analytics manager files (`MixpanelManager.swift`, `PostHogManager.swift`, `HeapManager.swift`, `AnalyticsManager.swift`) — replaced with no-op stubs
- [x] **1b** — Remove analytics/telemetry SPM packages (`mixpanel-swift`, `posthog-ios`, `heap-swift-core-sdk`, `sentry-cocoa`, `firebase-ios-sdk`)
- [x] **1c** — Remove all Sentry calls from `Logger`, `ResourceMonitor`, `OmiApp`, `AuthService`, `FeedbackView`, `RewindStorage`, `VideoChunkEncoder`, `RewindOCRService`
- [x] **1d** — `APIClient.swift` — point base URLs to `localhost:8080`
- [x] **1e** — `AuthService.swift` — replace Firebase OAuth with local UUID token stored at `~/.ollami/token`; remove Firebase SPM package and `GoogleService-Info.plist`
- [x] **1f** — UI cleanup — remove cloud-only links and widgets:
  - `HelpPage.swift` — replaced Crisp cloud chat with GitHub repo link
  - `SidebarView.swift` — removed "Get Omi" promo widget, affiliate link, commented upgrade block
  - `ChatPage.swift` — removed "Upgrade Required" alert and iCloud sync badge
  - `SettingsSidebar.swift` — removed "Plan and Usage" subscription section from nav
  - `SettingsPage.swift` — removed Private Cloud Sync toggle, Google Cloud encryption card, omi.me links

### Remaining

- [x] **1g** — Add Ollami settings panel (new SwiftUI settings section):
  - Ollama base URL (default: `http://localhost:11434`)
  - Active model picker (fetched live from Ollama `/api/tags`)
  - Whisper model size selector (tiny / base / small / medium)
  - Backend URL (default: `http://localhost:8080`)
  - Plugin manager (add/remove webhook plugins by URL)

- [x] **1h** — Delete all non-desktop files from the repo — this is a macOS-only fork, not the full Omi monorepo. Remove:
  - `app/` — Flutter iOS/Android app
  - `backend/` — cloud Python backend (will be replaced by local backend in Phase 2)
  - `omi/` — firmware for the Omi wearable
  - `omiGlass/` — Omi Glasses firmware
  - `sdks/` — React Native, Python, Swift SDKs
  - `plugins/` — cloud plugin integrations
  - `docs/` — upstream Omi documentation
  - `mcp/` — Omi MCP server
  - `figma/` — design sync tooling
  - `legacy/` — old Flutter desktop app
  - `desktop/Auth-Python/` — OAuth server (replaced by local token)
  - `desktop/Backend-Rust/` — Rust backend (replaced by local Python)
  - `desktop/demo/` — demo assets

- [ ] **1i** — Rewrite `README.md` to describe Ollami instead of upstream Omi:
  - What it is (local-first macOS AI assistant)
  - Architecture diagram (Swift app → FastAPI → Ollama + faster-whisper + SQLite)
  - Prerequisites (Ollama, Python 3.11+, macOS 14+)
  - Setup / run instructions

---

## Phase 2 — Local Python Backend

Replace the upstream cloud backend with a self-contained FastAPI server.

- [ ] **2a** — SQLite schema + SQLAlchemy models (replaces Firestore)
- [ ] **2b** — faster-whisper WebSocket STT handler (replaces Deepgram)
- [ ] **2c** — Ollama LLM client + rewire all chat/memory/summary routes (replaces OpenAI/Anthropic)
- [ ] **2d** — Chroma vector store + local `nomic-embed-text` embeddings (replaces Pinecone + Typesense)
- [ ] **2e** — Local filesystem storage at `~/.ollami/data/` (replaces GCS)
- [ ] **2f** — Single-user local token auth middleware (replaces Firebase Auth)
- [ ] **2g** — Trim routers from ~42 to ~15 keepers; delete payment, phone, OAuth, telemetry, firmware, announcement routers
- [ ] **2h** — Plugin webhook dispatcher (`on_conversation_end`, `on_memory_created`, `on_chat_message`)
- [ ] **2i** — `requirements.txt` — strip to local-only dependencies (~180 packages removed)
- [ ] **2j** — `backend/.env.local` — local config file with Ollama/Whisper/SQLite paths

---

## Phase 3 — Plugin Support UI

- [ ] **3a** — Plugin CRUD API (`GET/POST/DELETE /v1/plugins`) backed by SQLite
- [ ] **3b** — Plugin manager in Swift settings panel (add by URL, select trigger events, enable/disable)

---

## Phase 4 — Performance & Polish

- [ ] **4a** — Whisper model benchmarking on Apple Silicon (latency/accuracy by size)
- [ ] **4b** — Ollama model benchmarking per task (qwen2.5 vs llama3.2 vs mistral)
- [ ] **4c** — Local Ollama tool-calling agent (replaces `acp-bridge`)
- [ ] **4d** — Local TTS — Kokoro-TTS or piper-tts (replaces ElevenLabs)
- [ ] **4e** — Conversation export/import to JSON
- [ ] **4f** — `scripts/start.sh` — launcher that checks Ollama → starts backend → opens app

---

## Out of Scope

These will never be in Ollami:
- iOS / Android app
- Wearable device support (omi hardware, omiGlass)
- Web admin panel
- Multi-user support
- Cloud sync
- Subscription / payment system
