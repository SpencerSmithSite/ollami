import asyncio
import os
import re
import subprocess
import tempfile
from pathlib import Path

_SAY = "/usr/bin/say"
_AFCONVERT = "/usr/bin/afconvert"

_DEFAULT_VOICE = os.getenv("TTS_VOICE", "Samantha")
_DEFAULT_RATE = int(os.getenv("TTS_RATE", "175"))  # words per minute

_VOICE_RE = re.compile(r"^(.+?)\s{2,}([a-z]{2}_[A-Z]{2})\s")


def list_voices() -> list[dict]:
    """Return voices available on this Mac via `say -v ?`."""
    try:
        result = subprocess.run([_SAY, "-v", "?"], capture_output=True, text=True, check=True)
    except Exception:
        return [{"name": _DEFAULT_VOICE, "locale": "en_US"}]

    voices = []
    for line in result.stdout.splitlines():
        m = _VOICE_RE.match(line)
        if m:
            voices.append({"name": m.group(1).strip(), "locale": m.group(2)})
    return voices


async def synthesize(text: str, voice: str | None = None, rate: int | None = None) -> bytes:
    """Synthesize *text* to WAV bytes via macOS say + afconvert."""
    v = voice or _DEFAULT_VOICE
    r = rate or _DEFAULT_RATE

    with tempfile.TemporaryDirectory() as tmpdir:
        aiff_path = str(Path(tmpdir) / "out.aiff")
        wav_path = str(Path(tmpdir) / "out.wav")

        await asyncio.to_thread(
            subprocess.run,
            [_SAY, "-v", v, "-r", str(r), "-o", aiff_path, text],
            check=True,
        )
        await asyncio.to_thread(
            subprocess.run,
            [_AFCONVERT, aiff_path, wav_path, "-d", "LEI16@22050", "-f", "WAVE"],
            check=True,
        )
        return Path(wav_path).read_bytes()
