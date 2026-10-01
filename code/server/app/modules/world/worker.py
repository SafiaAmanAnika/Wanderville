"""Run `python -m app.modules.world.worker` separately from API processes.

Bounded player batches; multiple workers serialize each player's actions. Weather
is computed from the shared game clock, so no process-local scheduling state exists.
"""

import argparse
import time
from datetime import timedelta
from sqlalchemy import delete, select
from app.core.clock import utcnow, as_utc
from app.core.gameplay import game_day
from app.db import model_registry  # noqa: F401
from app.db.session import SessionLocal, transaction
from app.modules.players.models import Player
from app.modules.players.repository import PlayerRepository
from app.modules.world.service import WorldService
from app.modules.farming.service import FarmingService
from app.modules.notifications.service import NotificationsService
from app.modules.events.models import WorldEvent
from app.modules.realtime.models import NearbyMessage
from app.modules.social.models import Invite


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
    for pid in ids:
        with transaction(db):
            if not PlayerRepository(db).lock(pid):
                continue
            farm = FarmingService(db)
            state = farm.world.raw_state()
            environment = farm.world.state(now)
            world = farm.world.own_world(pid)
            for tile in farm.repo.list(world.id):
                if not tile.crop_item_code:
                    continue
                farm._persist_growth(tile, state, now)
                if (
                    environment.is_raining
                    and tile.growth_stage < 3
                    and not tile.is_watered
                ):
                    tile.is_watered = True
                    tile.watered_at = now
                    NotificationsService(db).emit(
                        pid,
                        "rain",
                        "Rain watered your crops",
                        "/farm/plots",
                        f"rain:{game_day(db, now)}",
                    )
                if tile.growth_stage == 3:
                    key = f"crop:{tile.id}:{as_utc(tile.planted_at).isoformat()}"
                    NotificationsService(db).emit(
                        pid,
                        "crop_ready",
                        "A crop is ready to harvest",
                        f"/farm/plots/{tile.id}",
                        key,
                    )
            for invite in db.scalars(
                select(Invite).where(
                    Invite.sender_id == pid,
                    Invite.accepted.is_(False),
                    Invite.expires_at <= now,
                )
            ):
                NotificationsService(db).emit(
                    pid,
                    "invite_expired",
                    "A farm invitation expired",
                    "/social/invites",
                    f"invite_expired:{invite.id}",
                )
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
