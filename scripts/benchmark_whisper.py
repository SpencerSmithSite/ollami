#!/usr/bin/env python3
"""
Whisper model benchmark — measures load time and RTF (real-time factor)
for each model size on Apple Silicon (tiny, base, small, medium).

Runs against the backend venv when available; falls back to any Python
that has faster-whisper installed.

Usage:
    # synthetic audio (440 Hz sine, 5 s):
    ./backend/.venv/bin/python scripts/benchmark_whisper.py

    # real speech WAV (16-bit, 16 kHz, mono):
    ./backend/.venv/bin/python scripts/benchmark_whisper.py --audio sample.wav

    # subset of models:
    ./backend/.venv/bin/python scripts/benchmark_whisper.py --models tiny base
"""

import argparse
import math
import os
import struct
import sys

MODELS = ["tiny", "base", "small", "medium"]
SAMPLE_RATE = 16_000
DEFAULT_DURATION_S = 5.0


def _add_venv_to_path() -> None:
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    venv_site = os.path.join(repo_root, "backend", ".venv", "lib")
    if os.path.isdir(venv_site):
        import glob
        for sp in glob.glob(os.path.join(venv_site, "python3*", "site-packages")):
            if sp not in sys.path:
                sys.path.insert(0, sp)


_add_venv_to_path()


def generate_test_audio(duration_s: float = DEFAULT_DURATION_S) -> bytes:
    """440 Hz sine + 200 Hz undertone as 16-bit LE PCM. Keeps VAD engaged."""
    n = int(SAMPLE_RATE * duration_s)
    samples = [
        int((math.sin(2 * math.pi * 440.0 * i / SAMPLE_RATE) * 0.7
             + math.sin(2 * math.pi * 200.0 * i / SAMPLE_RATE) * 0.3)
            * 16383)
        for i in range(n)
    ]
    return struct.pack(f"<{n}h", *samples)


def load_wav(path: str) -> bytes:
    import wave
    with wave.open(path, "rb") as wf:
        if wf.getsampwidth() != 2:
            sys.exit(f"ERROR: {path} must be 16-bit PCM (got {wf.getsampwidth() * 8}-bit)")
        if wf.getframerate() != SAMPLE_RATE:
            sys.exit(f"ERROR: {path} must be 16 kHz (got {wf.getframerate()} Hz)")
        if wf.getnchannels() != 1:
            sys.exit(f"ERROR: {path} must be mono (got {wf.getnchannels()} channels)")
        return wf.readframes(wf.getnframes())


def benchmark(model_size: str, pcm: bytes) -> dict:
    try:
        import numpy as np
        from faster_whisper import WhisperModel
    except ImportError as exc:
        return {"error": f"import failed: {exc}"}

    import time

    audio = np.frombuffer(pcm, dtype=np.int16).astype(np.float32) / 32768.0
    audio_s = len(audio) / SAMPLE_RATE

    t0 = time.perf_counter()
    model = WhisperModel(model_size, device="cpu", compute_type="int8")
    load_s = time.perf_counter() - t0

    t1 = time.perf_counter()
    segments, _ = model.transcribe(
        audio,
        beam_size=1,
        vad_filter=True,
        vad_parameters={"min_silence_duration_ms": 300},
    )
    text = " ".join(s.text.strip() for s in segments)
    transcribe_s = time.perf_counter() - t1

    del model

    return {
        "model": model_size,
        "load_s": round(load_s, 2),
        "audio_s": round(audio_s, 1),
        "transcribe_s": round(transcribe_s, 2),
        "rtf": round(transcribe_s / audio_s, 3),
        "output": (text[:80] + "…") if len(text) > 80 else (text or "(silence / no speech detected)"),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Benchmark faster-whisper model sizes")
    parser.add_argument("--audio", help="16-bit 16 kHz mono WAV file to transcribe")
    parser.add_argument(
        "--models", nargs="+", default=MODELS,
        choices=MODELS, metavar="MODEL",
        help=f"Models to test (default: {' '.join(MODELS)})",
    )
    args = parser.parse_args()

    if args.audio:
        print(f"Loading audio from {args.audio} …")
        pcm = load_wav(args.audio)
    else:
        print(f"Generating {DEFAULT_DURATION_S}s synthetic audio (no --audio provided) …")
        pcm = generate_test_audio(DEFAULT_DURATION_S)

    audio_s = len(pcm) // 2 / SAMPLE_RATE
    print(f"Audio: {audio_s:.1f}s  |  device: cpu  |  compute_type: int8\n")

    col = "{:<10} {:>10} {:>16} {:>8}  {}"
    print(col.format("Model", "Load (s)", "Transcribe (s)", "RTF", "Output"))
    print("-" * 95)

    for size in args.models:
        print(f"  [{size}] …", end="\r", flush=True)
        res = benchmark(size, pcm)
        if "error" in res:
            print(col.format(size, "ERROR", "", "", res["error"]))
        else:
            print(col.format(
                res["model"],
                res["load_s"],
                res["transcribe_s"],
                res["rtf"],
                res["output"],
            ))

    print()
    print("RTF = transcribe time / audio duration.  RTF < 1.0 → faster-than-real-time.")
    print("Note: load time is one-time per process; only transcribe time matters at runtime.")


if __name__ == "__main__":
    main()
