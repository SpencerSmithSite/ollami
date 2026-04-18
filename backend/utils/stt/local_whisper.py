import os
from collections.abc import Iterator
from typing import NamedTuple

import numpy as np
import torch
from faster_whisper import WhisperModel
from silero_vad import VADIterator, load_silero_vad

SAMPLE_RATE = 16_000
# silero-vad requires exactly 512-sample chunks at 16 kHz
VAD_CHUNK_SAMPLES = 512

_vad_model = load_silero_vad()


class Segment(NamedTuple):
    text: str
    speaker: str
    start: float
    end: float
    is_final: bool


class WhisperSTT:
    def __init__(self) -> None:
        model_size = os.getenv("WHISPER_MODEL_SIZE", "small")
        # CTranslate2 does not support Apple MPS; CPU with int8 is fast on Apple Silicon
        self._model = WhisperModel(model_size, device="cpu", compute_type="int8")

    def make_vad_iterator(self) -> VADIterator:
        return VADIterator(_vad_model, sampling_rate=SAMPLE_RATE)

    def transcribe(self, pcm_bytes: bytes) -> Iterator[Segment]:
        if not pcm_bytes:
            return
        audio = np.frombuffer(pcm_bytes, dtype=np.int16).astype(np.float32) / 32768.0
        segments, _ = self._model.transcribe(
            audio,
            beam_size=5,
            word_timestamps=True,
            vad_filter=True,
            vad_parameters={"min_silence_duration_ms": 300},
        )
        for seg in segments:
            text = seg.text.strip()
            if text:
                yield Segment(
                    text=text,
                    # Speaker diarisation placeholder — pyannote.audio integration
                    # requires a HuggingFace token and is wired in separately.
                    speaker="SPEAKER_00",
                    start=seg.start,
                    end=seg.end,
                    is_final=True,
                )


_instance: WhisperSTT | None = None


def get_whisper() -> WhisperSTT:
    global _instance
    if _instance is None:
        _instance = WhisperSTT()
    return _instance
