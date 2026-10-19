"""Private API for the Godot dedicated server.

This half is *not* for game clients. It authenticates the **host**, not the
player: a shared server-only secret presented in a header, compared in constant
time, and never returned by any endpoint. A client that learns nothing about it
cannot reach these routes at all.

Threat model, stated plainly: this is a shared bearer secret over HTTP. It is
adequate for the documented local development setup, where the backend and the
Godot host run on one machine and ``MULTIPLAYER_HOST_ALLOWLIST`` restricts the
peer address to loopback. It is *not* a production design for a public
deployment -- see the transport notes in the docs. ENet itself is unencrypted,
so the secret and the ticket both travel in the clear unless the pair is kept on
a trusted network or wrapped in TLS.
"""

import math

from fastapi import APIRouter, Depends, Header, Request
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.clock import utcnow
from app.core.config import settings
from app.core.responses import success
from app.db.session import get_db
from app.modules.realtime import admission, position_projection
from app.modules.realtime.models import Presence
from app.modules.realtime.tickets import constant_time_matches
from app.modules.world.models import CAMPUS_ROOM

router = APIRouter(prefix="/internal/multiplayer", tags=["internal-multiplayer"])

_UNCONFIGURED = (
    "Multiplayer admission is not configured: set MULTIPLAYER_BRIDGE_SECRET "
    "on the backend before starting a Godot multiplayer server."
)


def require_host(
    request: Request,
    x_multiplayer_secret: str | None = Header(default=None),
):
    """Authenticate the calling Godot host, or refuse.

    Fails closed on every path: an unset secret rejects everybody rather than
    accepting an empty header, and the allowlist is checked before the secret so
    a non-local caller never reaches the comparison at all.
    """
    expected = settings.multiplayer_bridge_secret
    if not expected:
        from app.core.exceptions import Forbidden

        raise Forbidden(_UNCONFIGURED)

    if not constant_time_matches(x_multiplayer_secret or "", expected):
        import logging

        from app.core.exceptions import Forbidden

        # Never log the presented value; log only its shape, which is what is
        # needed to tell a missing header from a wrong secret.
        logging.getLogger("wanderville").warning(
            "multiplayer host rejected: header_present=%s length=%d expected_length=%d",
            x_multiplayer_secret is not None,
            len(x_multiplayer_secret or ""),
            len(expected),
        )
        raise Forbidden("Invalid multiplayer host credentials")

    if settings.multiplayer_host_allowlist:
        allowed = [
            entry.strip()
            for entry in settings.multiplayer_host_allowlist.split(",")
            if entry.strip()
        ]
        peer = request.client.host if request.client else None
        if peer not in allowed:
            from app.core.exceptions import Forbidden

            raise Forbidden("Multiplayer host address is not allowed")


class ConsumeRequest(BaseModel):
    ticket: str = Field(min_length=8, max_length=256)
    server_id: str = Field(default="", max_length=64)


@router.post("/tickets/consume", dependencies=[Depends(require_host)])
def consume_ticket(
    payload: ConsumeRequest,
    db: Session = Depends(get_db),
):
    """Spend a ticket and return the authoritative identity behind it."""
    return success(admission.admit(db, payload.ticket, payload.server_id))


@router.post("/tickets/introspect", dependencies=[Depends(require_host)])
def introspect_ticket(
    payload: ConsumeRequest,
    db: Session = Depends(get_db),
):
    """Inspect a ticket without spending it, for server-side diagnostics."""
    return success(admission.introspect(db, payload.ticket))


class PresenceUpdate(BaseModel):
    player_id: int = Field(gt=0)
    x: float
    y: float
    sequence: int = Field(default=0, ge=0)


class PresencePush(BaseModel):
    """A batch of authoritative campus positions from the movement host."""

    server_id: str = Field(default="", max_length=64)
    updates: list[PresenceUpdate] = Field(default_factory=list, max_length=256)
    leaves: list[int] = Field(default_factory=list, max_length=256)


@router.post("/presence", dependencies=[Depends(require_host)])
def push_presence(
    payload: PresencePush,
    db: Session = Depends(get_db),
):
    """Record the movement host's live campus positions into the projection.

    The host is trusted -- it computed these positions with its own physics --
    but the *room* is not taken from the host. Each update is matched to the
    player's own ``player_presence`` row, and only a campus row is accepted, so a
    host cannot place a player into a farm they are not standing in. Coordinates
    go to the in-memory projection, never to a per-step PostgreSQL write; the
    durable row keeps the last committed position and the socket heartbeat keeps
    it live.

    Unknown players and non-campus rooms are skipped rather than rejected, so one
    stale row cannot make the whole batch fail.
    """
    now = utcnow()
    for player_id in payload.leaves:
        position_projection.drop(int(player_id))

    wanted = [int(update.player_id) for update in payload.updates]
    rows = {}
    if wanted:
        rows = {
            row.player_id: row
            for row in db.scalars(select(Presence).where(Presence.player_id.in_(wanted)))
        }

    updated = 0
    skipped = 0
    for update in payload.updates:
        player_id = int(update.player_id)
        row = rows.get(player_id)
        if row is None or row.room != CAMPUS_ROOM:
            skipped += 1
            continue
        x, y = float(update.x), float(update.y)
        if not (math.isfinite(x) and math.isfinite(y)):
            skipped += 1
            continue
        position_projection.commit(
            player_id, row.room, x, y, int(update.sequence), row.room_epoch, now
        )
        updated += 1

    return success(
        {
            "ok": True,
            "updated": updated,
            "skipped": skipped,
            "left": len(payload.leaves),
        }
    )


@router.get("/health", dependencies=[Depends(require_host)])
def host_health():
    """Let the Godot server confirm it can reach the backend before listening."""
    from app.modules.realtime.tickets import registry

    return success(
        {
            "ok": True,
            "outstanding_tickets": registry.size(),
            "ticket_ttl_seconds": settings.multiplayer_ticket_ttl_seconds,
        }
    )