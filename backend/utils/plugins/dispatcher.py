import logging
from typing import Any

import httpx

from database.db import SessionLocal
from database.models import Plugin

logger = logging.getLogger(__name__)

_TIMEOUT = 5.0  # seconds per outbound webhook call

# Valid trigger names (mirrors Plugin.trigger column values)
ON_CONVERSATION_END = "on_conversation_end"
ON_MEMORY_CREATED = "on_memory_created"
ON_CHAT_MESSAGE = "on_chat_message"


async def dispatch(trigger: str, payload: dict[str, Any]) -> None:
    """Fire POST webhooks for every enabled plugin matching trigger. Never raises."""
    db = SessionLocal()
    try:
        urls = [
            p.webhook_url
            for p in db.query(Plugin).filter(Plugin.trigger == trigger, Plugin.enabled == True).all()  # noqa: E712
        ]
    finally:
        db.close()

    if not urls:
        return

    body = {"trigger": trigger, "payload": payload}
    async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
        for url in urls:
            try:
                await client.post(url, json=body)
            except Exception as exc:
                logger.warning("plugin webhook failed url=%s trigger=%s err=%s", url, trigger, exc)
