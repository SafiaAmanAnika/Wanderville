import secrets
from datetime import timedelta
from app.core.clock import as_utc, utcnow
from app.core.exceptions import AppError, NotFound
from app.core.gameplay import public
from app.db.session import transaction
from app.modules.fishing.models import FishingSpot, FishingSession, GroundDrop
from app.modules.fishing.repository import FishingRepository
from app.modules.shop.models import ItemRule
from app.modules.players.repository import PlayerRepository
from app.modules.inventory.service import InventoryService
from app.modules.economy.service import EconomyService
from app.modules.progression.service import ProgressionService
from app.modules.world.service import WorldService


class FishingService:
    def __init__(self, db):
        self.db, self.repo = db, FishingRepository(db)

    def cast(self, player_id, request, now=None):
        now = now or utcnow()
        with transaction(self.db):
            PlayerRepository(self.db).lock(player_id)
            from app.modules.realtime.service import RealtimeService
            from app.modules.world.geometry import at_water

            presence = RealtimeService(self.db).active(player_id)
            if presence.room != "campus" or not at_water(presence.x, presence.y):
                raise AppError("FISHING_SPOT_REQUIRED", "Stand near a campus lake")
            spot = self.repo.get(FishingSpot, request.spot_code)
            state = WorldService(self.db).state(now)
            if spot.freezes_in_winter and state.current_season == "winter":
                raise AppError(
                    "FROZEN_LAKE", "Fishing is unavailable at this frozen lake"
                )
            rule = self.repo.get(ItemRule, request.rod_code)
            inv = InventoryService(self.db)
            if not rule.fishing_rod or not inv.has_item(player_id, request.rod_code):
                raise AppError("ROD_REQUIRED", "You must own the selected fishing rod")
            if EconomyService(self.db).xp(player_id).level < rule.required_level:
                raise AppError("LEVEL_LOCKED", "Rod level requirement not met")
            row = self.repo.get(FishingSession, player_id, False)
            if row and not row.resolved and as_utc(row.expires_at) >= now:
                raise AppError("CAST_ACTIVE", "Finish the active cast first", 409)
            roll = secrets.randbelow(100)
            night = (
                state.current_time_of_day >= 0.75 or state.current_time_of_day < 0.25
            )
            item = (
                "lake_pearl"
                if roll < (12 if night else 4)
                else "golden_carp"
                if roll < 24
                else "river_carp"
            )
            values = dict(
                cast_id=secrets.token_hex(16),
                spot_code=spot.code,
                rod_code=request.rod_code,
                item_code=item,
                bite_at=now + timedelta(seconds=3 + secrets.randbelow(6)),
                resolved=False,
            )
            values["expires_at"] = values["bite_at"] + timedelta(seconds=2)
            if row:
                for k, v in values.items():
                    setattr(row, k, v)
            else:
                row = self.repo.add(FishingSession, player_id=player_id, **values)
        # Never expose the rolled reward until the catch is resolved.
        return {
            "cast_id": row.cast_id,
            "bite_at": row.bite_at,
            "expires_at": row.expires_at,
        }

    def catch(self, player_id, cast_id, now=None):
        now = now or utcnow()
        with transaction(self.db):
            PlayerRepository(self.db).lock(player_id)
            row = self.repo.get(FishingSession, player_id)
            if row.cast_id != cast_id or row.resolved:
                raise AppError(
                    "CAST_RESOLVED", "Cast is unavailable or already resolved", 409
                )
            if now < as_utc(row.bite_at):
                raise AppError("TOO_EARLY", "Wait for the bite")
            row.resolved = True
            if now > as_utc(row.expires_at):
                return {"caught": False, "reason": "Fish escaped"}
            inv, drop = InventoryService(self.db), None
            try:
                inv.add_internal(player_id, row.item_code)
            except AppError as exc:
                if exc.code != "INVENTORY_FULL":
                    raise
                drop = self.repo.add(
                    GroundDrop,
                    player_id=player_id,
                    item_code=row.item_code,
                    spot_code=row.spot_code,
                    expires_at=now + timedelta(minutes=5),
                )
            xp = (
                25
                if row.item_code == "lake_pearl"
                else 20
                if row.item_code == "golden_carp"
                else 8
            )
            EconomyService(self.db).gain_internal(player_id, xp)
            ProgressionService(self.db).record(player_id, "catch", now=now)
        return {
            "caught": True,
            "item_code": row.item_code,
            "xp": xp,
            "ground_drop": public(drop) if drop else None,
        }

    def claim(self, player_id, drop_id):
        with transaction(self.db):
            PlayerRepository(self.db).lock(player_id)
            row = self.repo.get(GroundDrop, drop_id)
            if row.player_id != player_id:
                raise NotFound()
            if row.claimed or as_utc(row.expires_at) <= utcnow():
                raise AppError("DROP_UNAVAILABLE", "Drop expired or was collected", 409)
            InventoryService(self.db).add_internal(player_id, row.item_code)
            row.claimed = True
        return {"item_code": row.item_code}

    def spots(self):
        return [public(r) for r in self.repo.list(FishingSpot)]

    def drops(self, player_id):
        return [
            public(r)
            for r in self.repo.list(
                GroundDrop,
                GroundDrop.player_id == player_id,
                GroundDrop.claimed.is_(False),
                GroundDrop.expires_at > utcnow(),
            )
        ]
