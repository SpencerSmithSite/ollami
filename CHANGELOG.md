# Changelog

## [Unreleased]

### Added
- `scripts/benchmark_whisper.py` (task 4a) — benchmarks faster-whisper model sizes (tiny/base/small/medium) on Apple Silicon; reports load time, transcription time, and real-time factor (RTF). Accepts an optional real WAV file via `--audio`; falls back to a synthetic 5-second tone.
- `scripts/benchmark_ollama.py` (task 4b) — benchmarks Ollama models (qwen2.5, llama3.2, mistral) across three tasks: chat, summarisation, and memory extraction; reports tokens/sec and elapsed time. Skips models not yet pulled with a pull hint.

### Completed earlier
- `scripts/start.sh` (task 4f) — launcher that checks Ollama, starts the backend, and opens the app.
- Conversation export/import to JSON (task 4e) — `GET /v1/conversations/export` and `POST /v1/conversations/import`.
- Plugin CRUD API + Swift plugin manager UI (tasks 3a/3b).
- Full local Python backend replacing cloud services (Phase 2).
- Swift app stripped of all telemetry and cloud dependencies (Phase 1).
