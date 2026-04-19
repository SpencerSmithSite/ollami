import json

import numpy as np
import torch
from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from utils.stt.local_whisper import SAMPLE_RATE, VAD_CHUNK_SAMPLES, get_whisper

router = APIRouter()

# 2 bytes per PCM16 sample
_VAD_CHUNK_BYTES = VAD_CHUNK_SAMPLES * 2
# Flush the buffer after 30 seconds of accumulated audio at most
_MAX_BUFFER_BYTES = SAMPLE_RATE * 30 * 2


@router.websocket("/v1/listen")
async def listen(ws: WebSocket) -> None:
    await ws.accept()
    whisper = get_whisper()
    vad = whisper.make_vad_iterator()

    # Bytes waiting to fill a complete 512-sample VAD chunk
    leftover = bytearray()
    # All PCM16 bytes accumulated since the last transcription flush
    pcm_buffer = bytearray()

    try:
        while True:
            data = await ws.receive_bytes()
            leftover.extend(data)

            while len(leftover) >= _VAD_CHUNK_BYTES:
                chunk_bytes = bytes(leftover[:_VAD_CHUNK_BYTES])
                del leftover[:_VAD_CHUNK_BYTES]

                pcm_buffer.extend(chunk_bytes)

                chunk = np.frombuffer(chunk_bytes, dtype=np.int16).astype(np.float32) / 32768.0
                vad_result = vad(torch.from_numpy(chunk), return_seconds=True)

                speech_ended = vad_result is not None and "end" in vad_result
                buffer_full = len(pcm_buffer) >= _MAX_BUFFER_BYTES

                if (speech_ended or buffer_full) and len(pcm_buffer) > 0:
                    for seg in whisper.transcribe(bytes(pcm_buffer)):
                        await ws.send_text(
                            json.dumps(
                                {
                                    "text": seg.text,
                                    "speaker": seg.speaker,
                                    "is_final": seg.is_final,
                                    "start": seg.start,
                                    "end": seg.end,
                                }
                            )
                        )
                    pcm_buffer.clear()
                    vad.reset_states()

    except WebSocketDisconnect:
        pcm_buffer.clear()
    except Exception as exc:
        try:
            await ws.close(code=1011, reason=str(exc))
        except Exception:
            pass
