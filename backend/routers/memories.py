from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from database.db import get_db
from database.models import Memory, User
from utils.memory.chroma_store import remove_memory, search_memories, upsert_memory
from utils.plugins.dispatcher import ON_MEMORY_CREATED, dispatch

router = APIRouter(prefix="/v1/memories", tags=["memories"])

_LOCAL_USER_ID = "local"


def _ensure_user(db: Session) -> User:
    user = db.get(User, _LOCAL_USER_ID)
    if user is None:
        user = User(id=_LOCAL_USER_ID, name="Local User")
        db.add(user)
        db.commit()
        db.refresh(user)
    return user


class MemoryIn(BaseModel):
    content: str


class SearchIn(BaseModel):
    query: str
    n_results: int = 5


class MemoryOut(BaseModel):
    id: str
    content: str
    created_at: datetime

    class Config:
        from_attributes = True


class MemorySearchResult(MemoryOut):
    distance: float


@router.get("", response_model=list[MemoryOut])
def list_memories(db: Session = Depends(get_db)):
    user = _ensure_user(db)
    return db.query(Memory).filter(Memory.user_id == user.id).order_by(Memory.created_at.desc()).all()


@router.post("", response_model=MemoryOut, status_code=201)
async def create_memory(body: MemoryIn, db: Session = Depends(get_db)):
    user = _ensure_user(db)
    m = Memory(user_id=user.id, content=body.content)
    db.add(m)
    db.commit()
    db.refresh(m)
    m.embedding_id = m.id
    await upsert_memory(m.id, m.content)
    db.commit()
    await dispatch(ON_MEMORY_CREATED, {"id": m.id, "content": m.content, "created_at": m.created_at.isoformat()})
    return m


@router.delete("/{memory_id}", status_code=204)
def delete_memory(memory_id: str, db: Session = Depends(get_db)):
    m = db.get(Memory, memory_id)
    if m is None:
        raise HTTPException(status_code=404, detail="memory not found")
    db.delete(m)
    db.commit()
    remove_memory(memory_id)


@router.post("/search", response_model=list[MemorySearchResult])
async def semantic_search(body: SearchIn, db: Session = Depends(get_db)):
    hits = await search_memories(body.query, body.n_results)
    results = []
    for h in hits:
        m = db.get(Memory, h["id"])
        if m is not None:
            results.append(
                MemorySearchResult(id=m.id, content=m.content, created_at=m.created_at, distance=h["distance"])
            )
    return results
