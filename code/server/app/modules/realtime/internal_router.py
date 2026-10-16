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

import ipaddress

from fastapi import APIRouter, Depends, Header, Request
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.responses import success
from app.db.session import get_db
from app.modules.realtime import admission
from app.modules.realtime.tickets import constant_time_matches

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

    if not x_multiplayer_secret or not constant_time_matches(
        x_multiplayer_secret, expected
    ):
        from app.core.exceptions import Forbidden

        raise Forbidden("Invalid multiplayer host credentials")


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