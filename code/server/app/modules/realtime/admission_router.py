"""Public multiplayer admission API.

This is the client-facing half. It requires the same access token as every other
player-facing endpoint, so there is no second login and no new credential for a
client to manage. It can only mint tickets; it cannot admit anybody, and it can
never see the internal host secret.
"""

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.core.rate_limit import rate_limit
from app.core.responses import success
from app.db.session import get_db
from app.modules.auth.dependencies import get_current_player_id
from app.modules.realtime import admission

router = APIRouter(prefix="/multiplayer", tags=["multiplayer"])


class TicketRequest(BaseModel):
    server_id: str = Field(default="", max_length=64)


class TicketResponse(BaseModel):
    ticket: str
    expires_at: object
    expires_in: int
    server_id: str
    transport: str


@router.post(
    "/tickets",
    response_model=None,
    dependencies=[Depends(rate_limit(30))],
)
def create_ticket(
    payload: TicketRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    """Mint a short-lived, single-use admission ticket for this player."""
    return success(admission.request_ticket(db, player_id, payload.server_id))


@router.get("/config")
def multiplayer_config():
    """What a client needs to know before it tries to connect."""
    from app.core.config import settings

    return success(
        {
            "transport_default": settings.multiplayer_transport,
            "ticket_ttl_seconds": settings.multiplayer_ticket_ttl_seconds,
            "host": settings.godot_multiplayer_host,
            "port": settings.godot_multiplayer_port,
        }
    )