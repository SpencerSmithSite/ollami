import secrets
import os
from pathlib import Path
from typing import Any

_TOKEN_PATH = Path(os.getenv("TOKEN_PATH", str(Path.home() / ".ollami" / "token")))

# Routes that never require auth (FastAPI metadata + health)
_PUBLIC_PATHS = {"/", "/docs", "/openapi.json", "/redoc"}

_cached_token: str | None = None


def load_token() -> str:
    """Return the single local auth token, generating and persisting it on first call."""
    global _cached_token
    if _cached_token is None:
        _TOKEN_PATH.parent.mkdir(parents=True, exist_ok=True)
        if not _TOKEN_PATH.exists():
            _cached_token = secrets.token_urlsafe(32)
            _TOKEN_PATH.write_text(_cached_token)
            _TOKEN_PATH.chmod(0o600)
        else:
            _cached_token = _TOKEN_PATH.read_text().strip()
    return _cached_token


class LocalAuthMiddleware:
    """Pure-ASGI middleware that validates Bearer tokens for both HTTP and WebSocket."""

    def __init__(self, app: Any) -> None:
        self.app = app

    async def __call__(self, scope: dict, receive: Any, send: Any) -> None:
        if scope["type"] not in ("http", "websocket"):
            await self.app(scope, receive, send)
            return

        if scope["path"] in _PUBLIC_PATHS:
            await self.app(scope, receive, send)
            return

        token = load_token()
        raw_headers = dict(scope.get("headers", []))

        auth_header = raw_headers.get(b"authorization", b"").decode()
        provided = auth_header[7:].strip() if auth_header.startswith("Bearer ") else ""

        # WebSocket: also accept token via ?token= query param
        if scope["type"] == "websocket" and not provided:
            for part in scope.get("query_string", b"").decode().split("&"):
                if part.startswith("token="):
                    provided = part[6:]
                    break

        if not provided or not secrets.compare_digest(provided, token):
            if scope["type"] == "http":
                await send(
                    {
                        "type": "http.response.start",
                        "status": 401,
                        "headers": [(b"content-type", b"application/json")],
                    }
                )
                await send({"type": "http.response.body", "body": b'{"detail":"unauthorized"}'})
            else:
                await send({"type": "websocket.close", "code": 4001})
            return

        await self.app(scope, receive, send)
