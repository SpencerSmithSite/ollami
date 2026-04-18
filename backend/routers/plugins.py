from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, HttpUrl
from sqlalchemy.orm import Session

from database.db import get_db
from database.models import Plugin
from utils.plugins.dispatcher import ON_CHAT_MESSAGE, ON_CONVERSATION_END, ON_MEMORY_CREATED

router = APIRouter(prefix="/v1/plugins", tags=["plugins"])

_VALID_TRIGGERS = {ON_CONVERSATION_END, ON_MEMORY_CREATED, ON_CHAT_MESSAGE}


class PluginIn(BaseModel):
    name: str
    trigger: str
    webhook_url: HttpUrl
    enabled: bool = True


class PluginPatch(BaseModel):
    enabled: bool | None = None
    name: str | None = None


class PluginOut(BaseModel):
    id: str
    name: str
    trigger: str
    webhook_url: str
    enabled: bool

    class Config:
        from_attributes = True


@router.get("", response_model=list[PluginOut])
def list_plugins(db: Session = Depends(get_db)):
    return db.query(Plugin).order_by(Plugin.name).all()


@router.post("", response_model=PluginOut, status_code=201)
def create_plugin(body: PluginIn, db: Session = Depends(get_db)):
    if body.trigger not in _VALID_TRIGGERS:
        raise HTTPException(
            status_code=422,
            detail=f"invalid trigger; valid values: {sorted(_VALID_TRIGGERS)}",
        )
    p = Plugin(
        name=body.name,
        trigger=body.trigger,
        webhook_url=str(body.webhook_url),
        enabled=body.enabled,
    )
    db.add(p)
    db.commit()
    db.refresh(p)
    return p


@router.get("/{plugin_id}", response_model=PluginOut)
def get_plugin(plugin_id: str, db: Session = Depends(get_db)):
    p = db.get(Plugin, plugin_id)
    if p is None:
        raise HTTPException(status_code=404, detail="plugin not found")
    return p


@router.patch("/{plugin_id}", response_model=PluginOut)
def update_plugin(plugin_id: str, body: PluginPatch, db: Session = Depends(get_db)):
    p = db.get(Plugin, plugin_id)
    if p is None:
        raise HTTPException(status_code=404, detail="plugin not found")
    if body.enabled is not None:
        p.enabled = body.enabled
    if body.name is not None:
        p.name = body.name
    db.commit()
    db.refresh(p)
    return p


@router.delete("/{plugin_id}", status_code=204)
def delete_plugin(plugin_id: str, db: Session = Depends(get_db)):
    p = db.get(Plugin, plugin_id)
    if p is None:
        raise HTTPException(status_code=404, detail="plugin not found")
    db.delete(p)
    db.commit()
