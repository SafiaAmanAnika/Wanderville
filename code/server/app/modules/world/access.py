"""The session model that makes world isolation explicit.

Every part of the system conflated two different things:

* who the caller **is** (``player_id``, from the access token), and
* which world their request is **about** (``world_id``).

Those are identical only while a player is standing in their own farm. The moment
one player stands in another's farm they diverge, and any code that assumed they
match either mutates the wrong world or leaks the right one to the wrong reader.

``resolve`` is the single place that derives the second fact, so no endpoint has
to re-derive it. ``require_owner`` is the single place that answers "may this
caller change persistent farm state?", which is always no for a visitor.
"""

from dataclasses import dataclass

from app.core.exceptions import AppError, Forbidden, NotFound
from app.modules.social.models import FarmVisitSession
from app.modules.world.models import PlayerWorld

MODE_OWNER = "OWNER"
MODE_VISITOR = "VISITOR"

# Product constant. The authoritative runtime cap is the per-world
# ``visitor_limit`` column, clamped to this value here so a row edited directly
# in the database can never raise the limit above five.
MAX_VISITORS_PER_FARM = 5


@dataclass(frozen=True)
class WorldSession:
    """Resolved identity + current world for one authenticated player."""

    player_id: int
    owned_world_id: int
    current_world_id: int
    session_mode: str
    host_player_id: int | None
    visit_session_id: int | None

    @property
    def is_owner(self) -> bool:
        return self.session_mode == MODE_OWNER

    @property
    def is_visitor(self) -> bool:
        return self.session_mode == MODE_VISITOR

    def public(self):
        return {
            "player_id": self.player_id,
            "owned_world_id": self.owned_world_id,
            "current_world_id": self.current_world_id,
            "session_mode": self.session_mode,
            "host_player_id": self.host_player_id,
            "visit_session_id": self.visit_session_id,
        }


def owned_world(db, player_id):
    """The one world this player owns, or 404 if it was never provisioned."""
    row = db.query(PlayerWorld).filter(PlayerWorld.owner_id == player_id).one_or_none()
    if row is None:
        raise NotFound("Player world has not been initialized")
    return row


def resolve(db, player_id):
    """Derive the full session for ``player_id``.

    Ownership is never inferred from the request: it is the row whose
    ``owner_id`` matches the authenticated player. An active visit session is the
    only thing that can make ``current_world_id`` differ from
    ``owned_world_id``, and it can never change what the player owns.
    """
    world = owned_world(db, player_id)
    visit = active_visit(db, player_id)
    if visit is not None:
        return WorldSession(
            player_id=player_id,
            owned_world_id=world.id,
            current_world_id=visit.world_id,
            session_mode=MODE_VISITOR,
            host_player_id=visit.host_player_id,
            visit_session_id=visit.id,
        )
    return WorldSession(
        player_id=player_id,
        owned_world_id=world.id,
        current_world_id=world.id,
        session_mode=MODE_OWNER,
        host_player_id=None,
        visit_session_id=None,
    )


def active_visit(db, visitor_player_id):
    return (
        db.query(FarmVisitSession)
        .filter(
            FarmVisitSession.visitor_player_id == visitor_player_id,
            FarmVisitSession.status == "ACTIVE",
        )
        .order_by(FarmVisitSession.id.desc())
        .first()
    )


def require_owner(db, player_id, world_id=None):
    """Authorize a persistent-world mutation.

    Ownership is decided by comparing the authenticated player against the
    world's ``owner_id`` on the server. A ``world_id`` supplied by the client is
    only ever used to look the row up, never as proof of permission, so a
    visitor replaying an owner payload is rejected here regardless of what they
    sent. Visitors can never reach this branch: an active visit session is
    rejected first, and only actions explicitly allow-listed as visitor-safe
    should ever bypass it.
    """
    session = resolve(db, player_id)
    if session.is_visitor:
        raise Forbidden(
            "Visiting a farm is read-only; you cannot change another player's farm"
        )
    world = db.get(PlayerWorld, world_id) if world_id else owned_world(db, player_id)
    if world is None:
        raise NotFound("World not found")
    if world.owner_id != player_id:
        # Never reveal that the world exists to a player who does not own it.
        raise NotFound("World not found")
    return world


def require_world_readable(db, player_id, world_id):
    """Authorize a read of somebody else's world.

    Used by the visitor snapshot, so it is the one read path that deliberately
    accepts a foreign ``world_id``. It requires an ACTIVE visit session to that
    exact world rather than friendship alone, so knowing an id is not enough.
    """
    visit = active_visit(db, player_id)
    if visit is None:
        raise Forbidden("Visit a farm before reading its state")
    if visit.world_id != world_id:
        raise Forbidden("You are not visiting this world")
    return db.get(PlayerWorld, world_id)


def active_visitor_count(db, world_id):
    return (
        db.query(FarmVisitSession.id)
        .filter(
            FarmVisitSession.world_id == world_id,
            FarmVisitSession.status == "ACTIVE",
        )
        .count()
    )


def capacity(db, world_id):
    """Free visitor slots for a world, resolved inside the caller's transaction."""
    world = db.get(PlayerWorld, world_id)
    if world is None:
        raise NotFound("World not found")
    limit = min(world.visitor_limit, MAX_VISITORS_PER_FARM)
    return max(0, limit - active_visitor_count(db, world_id)), limit


def farm_full_error():
    return AppError(
        "FARM_FULL",
        "This farm already has the maximum number of visitors",
        409,
    )