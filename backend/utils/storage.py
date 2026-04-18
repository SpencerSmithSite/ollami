import mimetypes
import os
import uuid
from pathlib import Path

_STORAGE_DIR = os.getenv("STORAGE_PATH", str(Path.home() / ".ollami" / "data" / "files"))


def _root() -> Path:
    p = Path(_STORAGE_DIR)
    p.mkdir(parents=True, exist_ok=True)
    return p


def save_file(data: bytes, original_filename: str) -> str:
    """Persist bytes to local storage and return a stable file_id (uuid + extension)."""
    ext = Path(original_filename).suffix.lower()
    file_id = str(uuid.uuid4()) + ext
    (_root() / file_id).write_bytes(data)
    return file_id


def get_file_path(file_id: str) -> Path | None:
    p = _root() / file_id
    return p if p.exists() else None


def delete_file(file_id: str) -> bool:
    p = _root() / file_id
    if p.exists():
        p.unlink()
        return True
    return False


def list_file_ids() -> list[str]:
    return sorted(f.name for f in _root().iterdir() if f.is_file())


def content_type_for(file_id: str) -> str:
    mime, _ = mimetypes.guess_type(file_id)
    return mime or "application/octet-stream"
