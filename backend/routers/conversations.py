import json
import re
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from database.db import get_db
from database.models import Conversation, Segment, User
from utils.llm.ollama_client import chat_model, get_ollama
from utils.plugins.dispatcher import ON_CONVERSATION_END, dispatch

router = APIRouter(prefix="/v1/conversations", tags=["conversations"])

_LOCAL_USER_ID = "local"


def _ensure_user(db: Session) -> User:
    user = db.get(User, _LOCAL_USER_ID)
    if user is None:
        user = User(id=_LOCAL_USER_ID, name="Local User")
        db.add(user)
        db.commit()
        db.refresh(user)
    return user


class SegmentIn(BaseModel):
    speaker: str | None = None
    text: str
    start_time: float | None = None
    end_time: float | None = None


class ConversationIn(BaseModel):
    transcript: str | None = None
    source: str | None = None
    segments: list[SegmentIn] = []


class ConversationOut(BaseModel):
    id: str
    title: str | None
    summary: str | None
    source: str | None
    created_at: datetime
    segment_count: int

    class Config:
        from_attributes = True


class ConversationDetail(ConversationOut):
    transcript: str | None
    segments: list[dict]
    action_items: list[dict]


@router.get("", response_model=list[ConversationOut])
def list_conversations(db: Session = Depends(get_db)):
    rows = db.query(Conversation).order_by(Conversation.created_at.desc()).all()
    return [
        ConversationOut(
            id=r.id,
            title=r.title,
            summary=r.summary,
            source=r.source,
            created_at=r.created_at,
            segment_count=len(r.segments),
        )
        for r in rows
    ]


@router.post("", response_model=ConversationOut, status_code=201)
async def create_conversation(body: ConversationIn, db: Session = Depends(get_db)):
    user = _ensure_user(db)
    conv = Conversation(user_id=user.id, transcript=body.transcript, source=body.source)
    db.add(conv)
    db.flush()
    for seg_in in body.segments:
        db.add(
            Segment(
                conversation_id=conv.id,
                speaker=seg_in.speaker,
                text=seg_in.text,
                start_time=seg_in.start_time,
                end_time=seg_in.end_time,
            )
        )
    db.commit()
    db.refresh(conv)
    out = ConversationOut(
        id=conv.id,
        title=conv.title,
        summary=conv.summary,
        source=conv.source,
        created_at=conv.created_at,
        segment_count=len(conv.segments),
    )
    await dispatch(
        ON_CONVERSATION_END,
        {
            "id": conv.id,
            "transcript": conv.transcript,
            "source": conv.source,
            "created_at": conv.created_at.isoformat(),
            "segment_count": len(conv.segments),
        },
    )
    return out


@router.get("/{conv_id}", response_model=ConversationDetail)
def get_conversation(conv_id: str, db: Session = Depends(get_db)):
    row = db.get(Conversation, conv_id)
    if row is None:
        raise HTTPException(status_code=404, detail="conversation not found")
    return ConversationDetail(
        id=row.id,
        title=row.title,
        summary=row.summary,
        source=row.source,
        created_at=row.created_at,
        segment_count=len(row.segments),
        transcript=row.transcript,
        segments=[
            {"id": s.id, "speaker": s.speaker, "text": s.text, "start": s.start_time, "end": s.end_time}
            for s in row.segments
        ],
        action_items=[{"id": a.id, "content": a.content, "completed": a.completed} for a in row.action_items],
    )


@router.delete("/{conv_id}", status_code=204)
def delete_conversation(conv_id: str, db: Session = Depends(get_db)):
    row = db.get(Conversation, conv_id)
    if row is None:
        raise HTTPException(status_code=404, detail="conversation not found")
    db.delete(row)
    db.commit()


@router.post("/{conv_id}/summarize")
async def summarize_conversation(conv_id: str, db: Session = Depends(get_db)):
    row = db.get(Conversation, conv_id)
    if row is None:
        raise HTTPException(status_code=404, detail="conversation not found")

    text = row.transcript or " ".join(s.text for s in row.segments)
    if not text.strip():
        raise HTTPException(status_code=422, detail="conversation has no transcript to summarize")

    resp = await get_ollama().chat.completions.create(
        model=chat_model(),
        messages=[
            {
                "role": "system",
                "content": (
                    "You are a concise summarizer. Given a conversation transcript, "
                    'produce a short title (max 8 words) and a 2-4 sentence summary. '
                    'Respond only in JSON: {"title": "...", "summary": "..."}'
                ),
            },
            {"role": "user", "content": text[:8000]},
        ],
    )

    raw = (resp.choices[0].message.content or "").strip()
    cleaned = re.sub(r"```(?:json)?\s*|\s*```", "", raw).strip()
    try:
        data = json.loads(cleaned)
        row.title = data.get("title") or row.title
        row.summary = data.get("summary") or row.summary
    except (json.JSONDecodeError, AttributeError):
        row.summary = raw[:1000]
    db.commit()
    return {"id": row.id, "title": row.title, "summary": row.summary}
