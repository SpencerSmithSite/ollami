import os

from openai import AsyncOpenAI

_OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434/v1")
_CHAT_MODEL_DEFAULT = "llama3.2"
_EMBED_MODEL_DEFAULT = "nomic-embed-text"

_client: AsyncOpenAI | None = None


def get_ollama() -> AsyncOpenAI:
    global _client
    if _client is None:
        _client = AsyncOpenAI(base_url=_OLLAMA_BASE_URL, api_key="ollama")
    return _client


def chat_model() -> str:
    return os.getenv("OLLAMA_CHAT_MODEL", _CHAT_MODEL_DEFAULT)


def embed_model() -> str:
    return os.getenv("OLLAMA_EMBED_MODEL", _EMBED_MODEL_DEFAULT)
