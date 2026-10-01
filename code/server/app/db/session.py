from contextlib import contextmanager

from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker

from app.core.config import settings


def make_engine(url: str, **kwargs):
    if url.startswith("sqlite"):
        kwargs.setdefault("connect_args", {"check_same_thread": False})
    engine = create_engine(url, pool_pre_ping=True, **kwargs)
    if engine.dialect.name == "sqlite":

        @event.listens_for(engine, "connect")
        def enable_foreign_keys(connection, _record):
            connection.execute("PRAGMA foreign_keys=ON")

    return engine


engine = make_engine(settings.database_url)
SessionLocal = sessionmaker(bind=engine, expire_on_commit=False, autoflush=False)


def get_db():
    with SessionLocal() as db:
        yield db


@contextmanager
def transaction(db):
    """One service action; includes any transaction begun by auth/read queries.

    Internal domain helpers flush only. Never nest this boundary.
    Cleanup catches BaseException only to rollback and immediately re-raise.
    """
    try:
        yield
        db.commit()
    except BaseException:
        db.rollback()
        raise
