"""Bounded, thread-safe in-memory projection of live player positions.

This is the ``PRESENCE_BACKEND=memory`` counterpart to the ``player_presence``
table. It exists so that walking does not cost a PostgreSQL commit and a roster
does not cost a distance-ordered ``SELECT`` several times a second per socket.

What is authoritative here, and what is not
-------------------------------------------
Only **live coordinates** are authoritative in memory. Everything that decides
*whether* a position may be seen or acted on stays in PostgreSQL:

* authentication, account state and token revocation
* farm ownership and accepted visit sessions
* blocks, friendships, privacy preferences
* room epochs and chat receipts

So a position can be trusted while the permission to share it is still decided
per read against the database. That is the whole point: the projection answers
"where is everybody", the database answers "who may see whom".

Trust rules
-----------
* A record only ever enters through :func:`commit`, which is called *after* the
  existing sequence/speed/collision/room checks have passed. No client
  coordinate can reach it unvalidated.
* A record that has never been committed is simply absent. An absent record is
  not evidence that a player is offline, so readers still resolve identity,
  username and permissions from the database.
* Records expire. An expired record is removed, never replaced by whatever
  PostgreSQL happens to hold -- restoring a stale coordinate from a durable row
  would silently teleport a player.
* Authorization changes drop or invalidate records, so a kicked visitor or a
  newly blocked player stops being a neighbour immediately.

This is per-process state, correct for the single-worker deployment this
project documents. It must not be read as support for several independent API
processes: two workers would hold two different maps, and each would report
only the players its own socket had seen.
"""

from dataclasses import dataclass, field
from threading import RLock

from app.core.clock import as_utc, utcnow


@dataclass
class LivePosition:
    """One player's last validated position."""

    player_id: int
    room: str
    x: float
    y: float
    sequence: int
    room_epoch: int
    updated_at: object


@dataclass
class PositionProjection:
    lock: RLock = field(default_factory=RLock)
    positions: dict = field(default_factory=dict)
    max_players: int = 512
    ttl_seconds: int = 15

    def sweep_locked(self, now):
        stale = [
            player_id
            for player_id, position in self.positions.items()
            if (now - as_utc(position.updated_at)).total_seconds() > self.ttl_seconds
        ]
        for player_id in stale:
            del self.positions[player_id]
        overflow = len(self.positions) - self.max_players
        if overflow > 0:
            for position in sorted(
                self.positions.values(), key=lambda p: p.updated_at
            )[:overflow]:
                self.positions.pop(position.player_id, None)


_projection = PositionProjection()


# ── writes ─────────────────────────────────────────────────────────────────


def commit(player_id, room, x, y, sequence, room_epoch, updated_at):
    """Record a position the caller has already validated and committed.

    Only ever called after the movement checks pass, so the projection cannot
    introduce a position the server did not authorise.
    """
    position = LivePosition(
        player_id=player_id,
        room=room,
        x=x,
        y=y,
        sequence=sequence,
        room_epoch=room_epoch,
        updated_at=updated_at,
    )
    now = utcnow()
    with _projection.lock:
        _projection.positions[player_id] = position
        _projection.sweep_locked(now)
    return position


def refresh(player_id, updated_at):
    """Mark an existing position as still live, without moving it.

    A heartbeat proves the socket is alive but says nothing about where the
    player is, so this updates only the freshness stamp and never the
    coordinates. Without it, a player standing still in a menu, on a fishing
    screen, or simply choosing not to walk would expire from the projection
    after the TTL while their connection was perfectly healthy.

    Returns True if a live position was refreshed.
    """
    with _projection.lock:
        position = _projection.positions.get(player_id)
        if position is None:
            return False
        position.updated_at = updated_at
        return True


def adopt(player_id, room, x, y, sequence, room_epoch, updated_at):
    """Record a position for a player the projection does not currently hold.

    Used when a healthy connection heartbeats but the in-memory record has
    expired or was never created: the durable ``player_presence`` row supplies
    the last accepted position, so the player rejoins the room where they were
    standing rather than at the default spawn. The coordinates still come from
    a row this server wrote after validating movement -- never from the client.
    """
    return commit(player_id, room, x, y, sequence, room_epoch, updated_at)


def drop(player_id):
    """Forget one player: disconnect, logout, room revocation, or a kick."""
    with _projection.lock:
        _projection.positions.pop(player_id, None)


def drop_room(room):
    """Forget everyone in a room, e.g. when the host of a farm disconnects."""
    with _projection.lock:
        for player_id, position in list(_projection.positions.items()):
            if position.room == room:
                del _projection.positions[player_id]


def reset():
    """Forget every position. Used by tests and an explicit runtime reset."""
    with _projection.lock:
        _projection.positions.clear()


def configure(max_players=None, ttl_seconds=None):
    with _projection.lock:
        if max_players is not None:
            _projection.max_players = max(1, int(max_players))
        if ttl_seconds is not None:
            _projection.ttl_seconds = max(1, int(ttl_seconds))
        _projection.sweep_locked(utcnow())


# ── reads ──────────────────────────────────────────────────────────────────


def get(player_id, now=None):
    """The live position for ``player_id``, or None if absent or expired."""
    now = now or utcnow()
    with _projection.lock:
        position = _projection.positions.get(player_id)
        if position is None:
            return None
        if (now - as_utc(position.updated_at)).total_seconds() > _projection.ttl_seconds:
            del _projection.positions[player_id]
            return None
        return position


def room_members(room, now=None):
    """Live positions in ``room``, oldest first, for a stable roster order."""
    now = now or utcnow()
    with _projection.lock:
        members = [
            position
            for position in _projection.positions.values()
            if position.room == room
            and (now - as_utc(position.updated_at)).total_seconds()
            <= _projection.ttl_seconds
        ]
    members.sort(key=lambda position: (position.updated_at, position.player_id))
    return members


def nearby(room, x, y, radius, now=None, exclude=None):
    """Live positions in ``room`` within ``radius``, nearest first.

    Mirrors ``RealtimeRepository.nearby``'s contract -- same room, same radius,
    nearest first -- so a caller can read one or the other interchangeably. It
    deliberately does not filter on ``updated_at`` ranges or authorization: an
    absent position must not be mistaken for "this player does not exist", so
    the caller still resolves eligibility from the database.
    """
    now = now or utcnow()
    exclude = exclude or set()
    radius_sq = radius * radius
    found = []
    for position in room_members(room, now):
        if position.player_id in exclude:
            continue
        dx = position.x - x
        dy = position.y - y
        if dx * dx + dy * dy <= radius_sq:
            found.append(position)
    found.sort(
        key=lambda position: (
            (position.x - x) ** 2 + (position.y - y) ** 2,
            position.player_id,
        )
    )
    return found


def room_ids(room, now=None):
    """Player ids with a live position in ``room``."""
    return {position.player_id for position in room_members(room, now)}


def size():
    with _projection.lock:
        return len(_projection.positions)


def member_ids():
    """Player ids with a live position, for assertions and diagnostics."""
    with _projection.lock:
        return set(_projection.positions)