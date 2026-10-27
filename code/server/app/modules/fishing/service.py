import secrets
from datetime import timedelta
from app.core.clock import as_utc, utcnow
from app.core.exceptions import AppError, NotFound
from app.core.responses import public
from app.core.progression import FISH_XP_BY_ITEM
from app.db.session import transaction
from app.modules.fishing.models import FishingSpot, FishingSession, GroundDrop
from app.db.repository import Repository
from app.modules.shop.models import ItemRule
from app.modules.players.repository import PlayerRepository
from app.modules.inventory.service import InventoryService
from app.modules.economy.service import EconomyService
from app.modules.progression.service import ProgressionService
from app.modules.realtime.service import RealtimeService
from app.modules.world.geometry import at_water
from app.modules.world.models import CAMPUS_ROOM
from app.modules.world.service import WorldService


# The fish the lake mini game can land. Anything outside this set is refused,
# so the client cannot name an arbitrary item and have it granted.
MINIGAME_FISH = frozenset({
    "bluegill", "sunfish", "carp", "catfish", "rainbow_trout",
    "largemouth_bass", "salmon", "pufferfish", "koi", "seahorse",
})


class FishingService:
    def __init__(self, db):
        self.db, self.repo = db, Repository(db)

    def cast(self, player_id, request, now=None):
        now = now or utcnow()
        with transaction(self.db):
            PlayerRepository(self.db).lock(player_id)
            presence = RealtimeService(self.db).active(player_id)
            if presence.room != CAMPUS_ROOM or not at_water(presence.x, presence.y):
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
                raise AppError("LEVEL_internal", "Rod level requirement not met")
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
            xp = FISH_XP_BY_ITEM[row.item_code]
            EconomyService(self.db).gain_internal(player_id, xp)
            ProgressionService(self.db).record(player_id, "catch", now=now)
        return {
            "caught": True,
            "item_code": row.item_code,
            "xp": xp,
            "ground_drop": public(drop) if drop else None,
        }

    def record_minigame_catch(self, player_id, item_code, now=None):
        """Store a fish the lake mini game caught.

        The mini game decides the fish and whether it was landed, so this is not
        the rolled cast/catch flow above: there is no cast to resolve and no
        rod requirement. The code is still checked against the fish the server
        knows, so an unknown or non-fish item can never be granted this way.
        """
        now = now or utcnow()
        if item_code not in MINIGAME_FISH:
            raise AppError("UNKNOWN_FISH", "That is not a fish you can catch", 400)
        with transaction(self.db):
            PlayerRepository(self.db).lock(player_id)
            InventoryService(self.db).add_internal(player_id, item_code)
            xp = FISH_XP_BY_ITEM.get(item_code, 0)
            if xp:
                EconomyService(self.db).gain_internal(player_id, xp)
            ProgressionService(self.db).record(player_id, "catch", now=now)
        return {"caught": True, "item_code": item_code, "xp": xp}


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
