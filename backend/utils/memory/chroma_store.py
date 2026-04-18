import os
from pathlib import Path

import chromadb

from utils.llm.ollama_client import embed_model, get_ollama

_CHROMA_PATH = os.getenv("CHROMA_PATH", str(Path.home() / ".ollami" / "data" / "chroma"))
_COLLECTION_NAME = "memories"

_client: chromadb.PersistentClient | None = None


def get_chroma() -> chromadb.PersistentClient:
    global _client
    if _client is None:
        Path(_CHROMA_PATH).mkdir(parents=True, exist_ok=True)
        _client = chromadb.PersistentClient(path=_CHROMA_PATH)
    return _client


def _collection() -> chromadb.Collection:
    return get_chroma().get_or_create_collection(_COLLECTION_NAME)


async def _embed(text: str) -> list[float]:
    resp = await get_ollama().embeddings.create(model=embed_model(), input=text)
    return resp.data[0].embedding


async def upsert_memory(memory_id: str, content: str) -> None:
    embedding = await _embed(content)
    _collection().upsert(ids=[memory_id], embeddings=[embedding], documents=[content])


def remove_memory(memory_id: str) -> None:
    try:
        _collection().delete(ids=[memory_id])
    except Exception:
        pass


async def search_memories(query: str, n_results: int = 5) -> list[dict]:
    col = _collection()
    count = col.count()
    if count == 0:
        return []
    embedding = await _embed(query)
    results = col.query(
        query_embeddings=[embedding],
        n_results=min(n_results, count),
        include=["documents", "distances"],
    )
    ids = results["ids"][0]
    docs = results["documents"][0]
    distances = results["distances"][0]
    return [{"id": ids[i], "content": docs[i], "distance": distances[i]} for i in range(len(ids))]
