#!/usr/bin/env bash
# Ollami launcher — checks Ollama, starts the backend, opens the app.
# Usage: bash scripts/start.sh

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${BLUE}[Ollami]${NC} $*"; }
ok()   { echo -e "${GREEN}  ✓${NC} $*"; }
warn() { echo -e "${YELLOW}  !${NC} $*"; }
fail() { echo -e "${RED}  ✗${NC} $*"; exit 1; }

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
BACKEND_DIR="$REPO_ROOT/backend"
VENV_DIR="$BACKEND_DIR/.venv"

# ── Config (can override via environment or .env.local) ───────────────────────
OLLAMA_URL="${OLLAMA_BASE_URL:-http://localhost:11434}"
BACKEND_PORT="${BACKEND_PORT:-8080}"
CHAT_MODEL="${OLLAMA_CHAT_MODEL:-llama3.2}"
EMBED_MODEL="${OLLAMA_EMBED_MODEL:-nomic-embed-text}"
APP_BUNDLE="${OLLAMI_APP:-/Applications/Omi Dev.app}"

echo ""
echo "  ╔═══════════════════════════════╗"
echo "  ║   Ollami — local AI assistant ║"
echo "  ╚═══════════════════════════════╝"
echo ""

# ── 1. Prerequisites ──────────────────────────────────────────────────────────
log "Checking prerequisites..."

command -v ollama >/dev/null 2>&1 || fail "ollama not found. Install from https://ollama.com"
ok "ollama found"

PYTHON=""
for candidate in python3.12 python3.11 python3; do
    if command -v "$candidate" >/dev/null 2>&1; then
        ver=$("$candidate" -c "import sys; v=sys.version_info; print(f'{v.major}.{v.minor}')" 2>/dev/null)
        major=${ver%%.*}; minor=${ver##*.}
        if [ "$major" -ge 3 ] && [ "$minor" -ge 11 ]; then
            PYTHON="$candidate"
            ok "Python $ver ($PYTHON)"
            break
        fi
    fi
done
[ -z "$PYTHON" ] && fail "Python 3.11+ not found. Install from https://python.org"

# ── 2. Ollama ─────────────────────────────────────────────────────────────────
echo ""
log "Checking Ollama..."

if curl -sf "$OLLAMA_URL/api/tags" >/dev/null 2>&1; then
    ok "Ollama already running at $OLLAMA_URL"
else
    log "Starting Ollama in the background..."
    ollama serve >/tmp/ollami-ollama.log 2>&1 &
    OLLAMA_PID=$!
    for i in $(seq 1 20); do
        curl -sf "$OLLAMA_URL/api/tags" >/dev/null 2>&1 && break
        sleep 0.5
    done
    if curl -sf "$OLLAMA_URL/api/tags" >/dev/null 2>&1; then
        ok "Ollama started (pid $OLLAMA_PID) — logs: /tmp/ollami-ollama.log"
    else
        fail "Ollama did not start after 10 s. Check /tmp/ollami-ollama.log"
    fi
fi

# ── 3. Required models ────────────────────────────────────────────────────────
echo ""
log "Checking required models..."

pull_if_missing() {
    local model="$1"
    if ollama list 2>/dev/null | awk 'NR>1 {print $1}' | grep -q "^${model}"; then
        ok "Model $model present"
    else
        log "Pulling $model (this may take a while on first run)..."
        if ollama pull "$model"; then
            ok "Pulled $model"
        else
            warn "Could not pull $model — some features may not work"
        fi
    fi
}

pull_if_missing "$CHAT_MODEL"
pull_if_missing "$EMBED_MODEL"

# ── 4. Backend ────────────────────────────────────────────────────────────────
echo ""
log "Checking backend..."

if curl -sf "http://127.0.0.1:$BACKEND_PORT/" >/dev/null 2>&1; then
    ok "Backend already running on port $BACKEND_PORT"
else
    # Create venv and install deps on first run
    if [ ! -f "$VENV_DIR/bin/uvicorn" ]; then
        log "Setting up Python environment (first-run, ~2 min)..."
        "$PYTHON" -m venv "$VENV_DIR" || fail "Could not create virtual environment"
        "$VENV_DIR/bin/pip" install -q --upgrade pip
        "$VENV_DIR/bin/pip" install -q -r "$BACKEND_DIR/requirements.txt" \
            || fail "Failed to install backend dependencies"
        ok "Python environment ready"
    fi

    log "Starting backend on port $BACKEND_PORT..."
    (cd "$BACKEND_DIR" && "$VENV_DIR/bin/uvicorn" main:app \
        --host 127.0.0.1 \
        --port "$BACKEND_PORT" \
        --log-level warning \
        2>&1) >/tmp/ollami-backend.log 2>&1 &
    BACKEND_PID=$!

    # Wait up to 60 s (Whisper model load can take time)
    log "Waiting for backend to be ready (loading Whisper model)..."
    for i in $(seq 1 60); do
        curl -sf "http://127.0.0.1:$BACKEND_PORT/" >/dev/null 2>&1 && break
        sleep 1
        printf "."
    done
    echo ""

    if curl -sf "http://127.0.0.1:$BACKEND_PORT/" >/dev/null 2>&1; then
        ok "Backend ready (pid $BACKEND_PID) — logs: /tmp/ollami-backend.log"
    else
        fail "Backend did not start. Check /tmp/ollami-backend.log"
    fi
fi

# ── 5. Open app ───────────────────────────────────────────────────────────────
echo ""
log "Opening Ollami..."

if [ -d "$APP_BUNDLE" ]; then
    open "$APP_BUNDLE"
    ok "Launched $APP_BUNDLE"
else
    warn "App not found at '$APP_BUNDLE'"
    warn "Build it first:  cd desktop && OMI_APP_NAME=Ollami ./run.sh"
    warn "Then set:        export OLLAMI_APP=/Applications/Ollami.app"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}  Ollami is running.${NC}"
echo "  Backend : http://127.0.0.1:$BACKEND_PORT"
echo "  Ollama  : $OLLAMA_URL"
echo "  Logs    : /tmp/ollami-backend.log  /tmp/ollami-ollama.log"
echo ""
