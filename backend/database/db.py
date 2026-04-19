import os
from collections.abc import Generator
from pathlib import Path

from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from database.models import Base

_DB_PATH = os.getenv("DB_PATH", str(Path.home() / ".ollami" / "ollami.db"))

_db_url = f"sqlite:///{_DB_PATH}"

engine = create_engine(
    _db_url,
    connect_args={"check_same_thread": False},  # required for SQLite + FastAPI threading
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def init_db() -> None:
    Path(_DB_PATH).parent.mkdir(parents=True, exist_ok=True)
    Base.metadata.create_all(bind=engine)


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
