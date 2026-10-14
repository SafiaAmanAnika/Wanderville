"""The one lock order and the shared keys for farm visiting.

Invitations and visit sessions are two files that both need to lock the same rows
in the same order. Keeping that order in one place is the entire point: a host
admitting a guest and that same guest leaving must take locks in the same
sequence, or they can deadlock against each other.

**The order is: every player row by ascending id, then the world row.** Never
reorder it, and never take a world lock before a player lock.
"""

from datetime import timedelta

from sqlalchemy import select

from app.modules.players.repository import PlayerRepository
from app.modules.world.models import PlayerWorld

INVITE_TTL = timedelta(minutes=10)

# How long a visit session may go without a heartbeat before the sweep reclaims
# the slot. Must comfortably exceed the client socket poll interval.
VISIT_HEARTBEAT_TIMEOUT = timedelta(seconds=90)

OPEN_STATUSES = ("PENDING", "ACCEPTED")
RESOLVED = ("DECLINED", "EXPIRED", "CANCELLED")


def active_key(host_id, guest_id, world_id):
    """Uniqueness key for one open invitation per (host, guest, world) triple."""
    return f"{host_id}:{guest_id}:{world_id}"


def lock_rows(db, *player_ids, world_id=None):
    """Take row locks in the global order: players ascending, then the world.

    Admission, leave and kick all call this, which is what makes them mutually
    deadlock-free rather than merely individually correct.
    """
    PlayerRepository(db).lock(
        *sorted({pid for pid in player_ids if pid is not None})
    )
    if world_id is not None:
        db.scalar(
            select(PlayerWorld)
            .where(PlayerWorld.id == world_id)
            .with_for_update()
            .execution_options(populate_existing=True)
        )