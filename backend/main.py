from contextlib import asynccontextmanager

from dotenv import load_dotenv

# Load .env.local before any module reads os.getenv at import time
load_dotenv(".env.local", override=False)

from fastapi import FastAPI

from database.db import init_db
from routers import chat, conversations, files, memories, transcribe
from utils.stt.local_whisper import get_whisper


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    get_whisper()  # pre-load Whisper + VAD models on startup
    yield


app = FastAPI(title="Ollami Backend", version="0.1.0", lifespan=lifespan)

app.include_router(transcribe.router)
app.include_router(conversations.router)
app.include_router(memories.router)
app.include_router(chat.router)
app.include_router(files.router)
