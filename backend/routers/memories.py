from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from database.db import get_db
from database.models import Memory, User

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


class MemoryOut(BaseModel):
    id: str
    content: str
    created_at: datetime

    class Config:
        from_attributes = True


@router.get("", response_model=list[MemoryOut])
def list_memories(db: Session = Depends(get_db)):
    user = _ensure_user(db)
    return db.query(Memory).filter(Memory.user_id == user.id).order_by(Memory.created_at.desc()).all()


@router.post("", response_model=MemoryOut, status_code=201)
def create_memory(body: MemoryIn, db: Session = Depends(get_db)):
    user = _ensure_user(db)
    m = Memory(user_id=user.id, content=body.content)
    db.add(m)
    db.commit()
    db.refresh(m)
    return m


@router.delete("/{memory_id}", status_code=204)
def delete_memory(memory_id: str, db: Session = Depends(get_db)):
    m = db.get(Memory, memory_id)
    if m is None:
        raise HTTPException(status_code=404, detail="memory not found")
    db.delete(m)
    db.commit()
