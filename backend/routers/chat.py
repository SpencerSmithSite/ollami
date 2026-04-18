import json
from collections.abc import AsyncIterator
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from sqlalchemy.orm import Session

from database.db import SessionLocal, get_db
from database.models import ChatSession, Message, User
from utils.llm.ollama_client import chat_model, get_ollama

router = APIRouter(prefix="/v1/chat", tags=["chat"])

_LOCAL_USER_ID = "local"


def _ensure_user(db: Session) -> User:
    user = db.get(User, _LOCAL_USER_ID)
    if user is None:
        user = User(id=_LOCAL_USER_ID, name="Local User")
        db.add(user)
        db.commit()
        db.refresh(user)
    return user


class SessionOut(BaseModel):
    id: str
    title: str | None
    created_at: datetime

    class Config:
        from_attributes = True


class SessionDetail(SessionOut):
    messages: list[dict]


class MessageIn(BaseModel):
    content: str


@router.get("/sessions", response_model=list[SessionOut])
def list_sessions(db: Session = Depends(get_db)):
    user = _ensure_user(db)
    return db.query(ChatSession).filter(ChatSession.user_id == user.id).order_by(ChatSession.created_at.desc()).all()


@router.post("/sessions", response_model=SessionOut, status_code=201)
def create_session(db: Session = Depends(get_db)):
    user = _ensure_user(db)
    s = ChatSession(user_id=user.id)
    db.add(s)
    db.commit()
    db.refresh(s)
    return s


@router.get("/sessions/{session_id}", response_model=SessionDetail)
def get_session(session_id: str, db: Session = Depends(get_db)):
    s = db.get(ChatSession, session_id)
    if s is None:
        raise HTTPException(status_code=404, detail="session not found")
    return SessionDetail(
        id=s.id,
        title=s.title,
        created_at=s.created_at,
        messages=[
            {"id": m.id, "role": m.role, "content": m.content, "created_at": m.created_at.isoformat()}
            for m in s.messages
        ],
    )


@router.delete("/sessions/{session_id}", status_code=204)
def delete_session(session_id: str, db: Session = Depends(get_db)):
    s = db.get(ChatSession, session_id)
    if s is None:
        raise HTTPException(status_code=404, detail="session not found")
    db.delete(s)
    db.commit()


async def _stream_reply(session_id: str, content: str) -> AsyncIterator[str]:
    db = SessionLocal()
    try:
        s = db.get(ChatSession, session_id)
        history = [{"role": m.role, "content": m.content} for m in s.messages]

        user_msg = Message(session_id=session_id, role="user", content=content)
        db.add(user_msg)
        db.commit()

        messages = history + [{"role": "user", "content": content}]
        stream = await get_ollama().chat.completions.create(
            model=chat_model(),
            messages=messages,
            stream=True,
        )

        full_reply: list[str] = []
        async for chunk in stream:
            delta = chunk.choices[0].delta.content if chunk.choices else None
            delta = delta or ""
            if delta:
                full_reply.append(delta)
                yield f"data: {json.dumps({'delta': delta})}\n\n"

        reply_text = "".join(full_reply)
        assistant_msg = Message(session_id=session_id, role="assistant", content=reply_text)
        db.add(assistant_msg)
        db.commit()
        yield "data: [DONE]\n\n"
    finally:
        db.close()


@router.post("/sessions/{session_id}/messages")
async def send_message(session_id: str, body: MessageIn, db: Session = Depends(get_db)):
    if db.get(ChatSession, session_id) is None:
        raise HTTPException(status_code=404, detail="session not found")
    return StreamingResponse(_stream_reply(session_id, body.content), media_type="text/event-stream")
