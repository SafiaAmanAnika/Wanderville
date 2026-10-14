"""Run `python -m app.modules.world.worker` separately from API processes.

Bounded player batches; multiple workers serialize each player's actions. Weather
is computed from the shared game clock, so no process-local scheduling state exists.
"""

import argparse
import time
from datetime import timedelta
from sqlalchemy import delete, select
from app.core.clock import utcnow, as_utc
from app.modules.world.service import game_day
from app.db import model_registry  # noqa: F401
from app.db.session import SessionLocal, transaction
from app.modules.players.models import Player
from app.modules.players.repository import PlayerRepository
from app.modules.world.service import WorldService
from app.modules.farming.service import FarmingService
from app.modules.notifications.service import NotificationsService
from app.modules.events.models import WorldEvent
from app.modules.realtime.models import NearbyMessage
from app.modules.social.community_models import ChatReceipt
from app.modules.social.farm_visiting import FarmVisitService
from app.modules.social.models import FarmInvitation


def sweep_visits(db, now=None):
    """Reclaim visitor slots and lapse unanswered invitations.

    The socket close path releases a slot the moment a connection drops. This
    is the backstop for the cases that never produce a close frame: a crashed
    client, a killed worker, or a network drop that silently times out. A
    visitor also has to be reclaimed when their *host* vanishes, because the
    visitor's own heartbeat stays healthy in that case. An unanswered invitation
    is marked EXPIRED here so the guest's inbox can say "expired" instead of
    offering an action that will fail.
    """
    now = now or utcnow()
    service = FarmVisitService(db)
    reclaimed = service.sweep_stale(now=now)
    orphaned = service.sweep_orphaned(now=now)
    lapsed = 0
    with transaction(db):
        expired = list(
            db.scalars(
                select(FarmInvitation).where(
                    FarmInvitation.status == "PENDING",
                    FarmInvitation.expires_at <= now,
                )
            )
        )
        for row in expired:
            row.status = "EXPIRED"
            row.active_key = None
            row.responded_at = now
            lapsed += 1
            NotificationsService(db).emit(
                row.invited_player_id,
                "farm_invitation_expired",
                "A farm invitation expired",
                "/farm/visiting/invitations",
                f"farm_invite_expired:{row.id}",
            )
    return {"stale": reclaimed, "orphaned": orphaned, "lapsed": lapsed}


def tick(db, now=None, after_id=0, batch_size=100):
    now = now or utcnow()
    ids = list(
        db.scalars(
            select(Player.id)
            .where(Player.id > after_id)
            .order_by(Player.id)
            .limit(batch_size)
        )
    )
    # Farm visits are not per-player, so they are swept once per pass rather
    # than inside the per-player loop.
    sweep_visits(db, now)
    for pid in ids:
        with transaction(db):
            if not PlayerRepository(db).lock(pid):
                continue
            FarmingService(db).advance_tiles(pid, now)
    with transaction(db):
        # Global event schedule: one 5-minute event every seventh in-game day.
        state = WorldService(db).repo.state(lock=True)
        day = game_day(db, now)
        start = as_utc(state.day_cycle_anchor_at) + timedelta(
            minutes=day * state.day_night_cycle_minutes
        )
        if day % 7 == 0:
            code = f"lake_discovery_{day}"
            if db.get(WorldEvent, code) is None:
                db.add(
                    WorldEvent(
                        code=code,
                        title="Rare Lake Discovery",
                        starts_at=start,
                        ends_at=start + timedelta(minutes=5),
                        item_code="lake_pearl",
                        quantity=1,
                    )
                )
        db.execute(delete(NearbyMessage).where(NearbyMessage.expires_at < now))
        db.execute(delete(ChatReceipt).where(ChatReceipt.expires_at < now))
    return ids[-1] if len(ids) == batch_size else 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--once", action="store_true")
    args = parser.parse_args()
    cursor = 0
    while True:
        with SessionLocal() as db:
            cursor = tick(db, after_id=cursor)
        if args.once and cursor == 0:
            break
        if cursor == 0:
            time.sleep(1)


if __name__ == "__main__":
    main()
