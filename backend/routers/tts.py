from fastapi import APIRouter, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel

from utils.tts.local_tts import list_voices, synthesize

router = APIRouter(prefix="/v1/tts", tags=["tts"])


class SynthesizeRequest(BaseModel):
    text: str
    voice: str | None = None
    rate: int | None = None


@router.get("/voices")
def get_voices():
    return list_voices()


@router.post("/synthesize")
async def synthesize_speech(body: SynthesizeRequest):
    if not body.text.strip():
        raise HTTPException(status_code=422, detail="text must not be empty")
    try:
        wav_bytes = await synthesize(body.text, voice=body.voice, rate=body.rate)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"TTS failed: {exc}") from exc
    return Response(content=wav_bytes, media_type="audio/wav")
