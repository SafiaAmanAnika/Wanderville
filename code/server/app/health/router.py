"""Liveness and readiness probes.

``/health`` proves the process is up and must never touch the database, so an
orchestrator does not restart a healthy process because the database is briefly
unavailable. ``/ready`` proves the process can actually serve traffic, which
means the schema is migrated and reference data is seeded.
"""

from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.core.exceptions import AppError
from app.core.responses import Envelope, success
from app.db.session import get_db

router = APIRouter(tags=["health"])

# The oldest schema revision this build knows how to serve. Readiness compares
# the numeric revision prefix against this floor rather than against a revision
# *name*, so adding a migration does not require editing application code.
MINIMUM_SCHEMA_REVISION = 8

# One seeded item is enough to prove reference seeding ran; wheat_seed is the
# item every crop chain needs, so its absence means the seed did not complete.
SEED_PROBE_ITEM = "wheat_seed"


def _revision_number(value):
    """Numeric prefix of an Alembic ``NNNN_name`` revision, or -1."""
    try:
        return int(str(value).split("_", 1)[0])
    except (TypeError, ValueError):
        return -1


@router.get("/health", response_model=Envelope[dict])
def health():
    return success({"status": "ok"})


@router.get("/ready", response_model=Envelope[dict])
def ready(db: Session = Depends(get_db)):
    db.execute(text("SELECT 1"))
    revision = db.scalar(text("SELECT version_num FROM alembic_version"))
    seeded = db.scalar(
        text(
            "SELECT count(*) FROM item_definitions i "
            "JOIN item_rules r ON r.item_code = i.item_code "
            "WHERE i.item_code = :code"
        ),
        {"code": SEED_PROBE_ITEM},
    )
    clock_ready = db.scalar(text("SELECT count(*) FROM world_state WHERE id = 1"))
    if (
        _revision_number(revision) < MINIMUM_SCHEMA_REVISION
        or not seeded
        or not clock_ready
    ):
        raise AppError(
            "DATABASE_NOT_READY", "Run database migrations and reference seeding", 503
        )
    return success({"status": "ready", "database": "connected"})