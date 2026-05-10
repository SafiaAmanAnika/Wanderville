from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.config import settings


class Base(DeclarativeBase):
    pass


# V1 database setup is synchronous; FastAPI routes can use the same SessionLocal later.
engine = create_engine(
    settings.database_url,
    # SQLite needs this for usage across threads (e.g. TestClient / Uvicorn workers).
    connect_args={"check_same_thread": False} if settings.database_url.startswith("sqlite") else {},
)

SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


def get_db():
    db: Session = SessionLocal()
    try:
        yield db
    finally:
        db.close()
