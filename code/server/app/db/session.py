from contextlib import contextmanager

from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker

from app.core.config import settings
from app.core.exceptions import TransactionBoundaryError


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


TRANSACTION_DEPTH_KEY = "_wanderville_transaction_depth"


@contextmanager
def transaction(db):
    """One service action; includes any transaction begun by auth/read queries.

    Internal domain helpers flush only and must not open this boundary. Nesting
    is rejected rather than tolerated: an inner exit would commit the outer
    caller's half-finished work and make the outer rollback a silent no-op.

    Cleanup catches BaseException only to rollback and immediately re-raise.
    """
    depth = db.info.get(TRANSACTION_DEPTH_KEY, 0)
    if depth:
        raise TransactionBoundaryError(
            "transaction() was entered while another service action was still "
            "open on the same session"
        )
    db.info[TRANSACTION_DEPTH_KEY] = depth + 1
    try:
        yield
        db.commit()
    except BaseException:
        db.rollback()
        raise
    finally:
        db.info[TRANSACTION_DEPTH_KEY] = depth
