"""Multiplayer admission: issue tickets to players, consume them for servers.

Two very different callers reach this module.

* A **game client** asks for a ticket over the ordinary authenticated HTTP API.
  It proves who it is with the same access token it already uses for everything
  else; there is no second login.
* The **Godot dedicated server** spends a ticket over a private, authenticated
  call. It never sees a player credential, and it learns the player identity
  only from what the registry hands back.

Account state is re-read at issue time, so a player who has been disabled or
unverified since logging in cannot obtain admission. At consume time the ticket
has already been bound to that verified player, and the session the caller
receives carries only the identity the backend chose -- never a client-supplied
player id.
"""

from dataclasses import dataclass

from app.core.clock import as_utc, utcnow
from app.core.config import settings
from app.core.exceptions import Forbidden
from app.db.session import transaction
from app.modules.auth.security import decode_access_token
from app.modules.players.models import Player
from app.modules.realtime.tickets import TicketError, consume_ticket, issue_ticket
from app.modules.world.access import resolve
from app.modules.world.models import CAMPUS_ROOM


@dataclass(frozen=True)
class AdmittedSession:
    """What a Godot host is told about a peer, and nothing more."""

    player_id: int
    username: str
    room: str
    room_epoch: int
    owned_world_id: int
    current_world_id: int
    session_mode: str
    host_player_id: int | None
    visit_session_id: int | None


def _verified_player(db, player_id: int) -> Player:
    """Re-read the account and refuse anything not currently usable.

    Deliberately not cached: this is the one place where "is this account still
    allowed in" is decided, and a stale answer would let a revoked player back
    onto the server.
    """
    player = db.get(Player, player_id)
    if player is None or not player.is_active or not player.email_verified:
        raise Forbidden("This account cannot join multiplayer")
    return player


def request_ticket(db, player_id: int, server_id: str = "") -> dict:
    """Mint a ticket for an already-authenticated player."""
    _verified_player(db, player_id)
    ticket = issue_ticket(player_id, server_id)
    return {
        "ticket": ticket.raw,
        "expires_at": ticket.expires_at,
        "expires_in": settings.multiplayer_ticket_ttl_seconds,
        "server_id": ticket.server_id,
        "transport": "godot-enet",
    }


def admit(db, raw_ticket: str, server_id: str = "") -> dict:
    """Spend a ticket and return the authoritative session for that player.

    Raises :class:`TicketError` for anything wrong with the ticket. The account
    is re-checked here as well, so revoking a player between issue and consume
    still closes the door.
    """
    try:
        record = consume_ticket(raw_ticket, server_id)
    except TicketError as exc:
        raise Forbidden(str(exc)) from exc

    player = db.get(Player, record.player_id)
    if player is None or not player.is_active or not player.email_verified:
        raise Forbidden("This account cannot join multiplayer")

    with transaction(db):
        # The world/visit session is derived here, never taken from the request,
        # so a host cannot be talked into admitting a player to a private farm.
        session = resolve(db, player.id)
        room = CAMPUS_ROOM
        if session.is_visitor:
            room = f"world:{session.current_world_id}"

    return {
        "player_id": session.player_id,
        "username": player.username,
        "room": room,
        "room_epoch": 0,
        "owned_world_id": session.owned_world_id,
        "current_world_id": session.current_world_id,
        "session_mode": session.session_mode,
        "host_player_id": session.host_player_id,
        "visit_session_id": session.visit_session_id,
        "issued_at": utcnow().isoformat(),
    }


def introspect(db, raw_ticket: str) -> dict:
    """Check a ticket without spending it. Server-side diagnostics only."""
    from app.modules.realtime.tickets import registry

    from app.modules.auth.security import hash_token

    record = registry._by_digest.get(hash_token(raw_ticket))  # noqa: SLF001
    if record is None:
        raise Forbidden("INVALID_TICKET")
    return {
        "player_id": record.player_id,
        "expires_at": record.expires_at,
        "expired": as_utc(record.expires_at) <= utcnow(),
        "server_id": record.server_id,
    }


def authenticated_player_id(token: str) -> int:
    """Validate an access token without a database round trip.

    Used by the internal endpoints, where the caller is the Godot host and the
    token is already known good. Deliberately not used for anything that grants
    a player rights.
    """
    player_id, _version = decode_access_token(token)
    return player_id