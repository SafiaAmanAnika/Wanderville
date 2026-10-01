from dataclasses import dataclass

from app.core.clock import as_utc, utcnow
from app.core.config import settings
from app.core.exceptions import AppError, NotFound
from app.db.session import transaction
from app.modules.economy.service import EconomyService
from app.modules.farming.repository import FarmingRepository
from app.modules.farming.schemas import (
    FarmGridResponse,
    FarmTileResponse,
    HarvestResponse,
    PlantResponse,
)
from app.modules.inventory.service import InventoryService
from app.modules.players.repository import PlayerRepository
from app.modules.world.service import WorldService, growth_seconds_between


@dataclass(frozen=True)
class Growth:
    progress: float
    stage: int
    watered: bool


def evaluate_growth(tile, state, now):
    """Four visible stages (0..3); one watering advances at most one stage.

    Unwatered elapsed time is discarded. Pure calculation permits read-only GETs.
    """
    if not tile.crop_item_code:
        return Growth(0.0, 0, False)
    progress, stage, watered = (
        tile.growth_progress_seconds,
        tile.growth_stage,
        tile.is_watered,
    )
    if watered and stage < 3:
        target = tile.item.growth_time_seconds * (stage + 1) / 3
        elapsed = growth_seconds_between(state, tile.last_growth_update_at, now)
        progress = min(target, progress + elapsed)
        if progress >= target - 1e-8:
            progress, stage, watered = target, stage + 1, False
    return Growth(progress, stage, watered)


def tile_response(tile, state, now):
    growth = evaluate_growth(tile, state, now)
    return FarmTileResponse(
        id=tile.id,
        x=tile.x,
        y=tile.y,
        item_code=tile.crop_item_code,
        is_tilled=tile.is_tilled,
        growth_progress_seconds=growth.progress,
        growth_stage=growth.stage,
        is_watered=growth.watered,
        planted_at=as_utc(tile.planted_at) if tile.planted_at else None,
        ready=bool(tile.crop_item_code) and growth.stage == 3,
    )


class FarmingService:
    def __init__(self, db):
        self.db, self.repo = db, FarmingRepository(db)
        self.players, self.world = PlayerRepository(db), WorldService(db)
        self.inventory, self.economy = InventoryService(db), EconomyService(db)

    def list(self, player_id, now=None):
        now, world, state = (
            now or utcnow(),
            self.world.own_world(player_id),
            self.world.raw_state(),
        )
        return FarmGridResponse(
            plots=[tile_response(r, state, now) for r in self.repo.list(world.id)],
            player_id=player_id,
        )

    def _owned(self, player_id, tile_id):
        tile = self.repo.owned(player_id, tile_id)
        if tile is None:
            raise NotFound("Farm tile not found")
        return tile

    def _persist_growth(self, tile, state, now):
        result = evaluate_growth(tile, state, now)
        tile.growth_progress_seconds = result.progress
        tile.growth_stage = result.stage
        tile.is_watered = result.watered
        tile.last_growth_update_at = max(
            as_utc(tile.last_growth_update_at), as_utc(now)
        )

    def till(self, player_id, request, now=None):
        now = now or utcnow()
        with transaction(self.db):
            self.players.lock(player_id)
            world, state = self.world.own_world(player_id), self.world.raw_state()
            tile = self.repo.coordinate(
                world.id, request.x, request.y
            ) or self.repo.create(world.id, request.x, request.y)
            tile.is_tilled = True
            self.db.flush()
            result = tile_response(tile, state, now)
        return result

    def plant(self, player_id, request, now=None):
        now = now or utcnow()
        with transaction(self.db):
            self.players.lock(player_id)
            world, state = self.world.own_world(player_id), self.world.raw_state()
            tile = self.repo.coordinate(world.id, request.x, request.y)
            if tile and tile.crop_item_code:
                raise AppError(
                    "FARM_PLOT_OCCUPIED", "This farm tile already has a crop", 409
                )
            item = self.inventory.definition(request.item_code)
            if not item.growth_time_seconds or not (
                item.category.endswith("_crop") or item.category == "rare_plant"
            ):
                raise AppError("INVALID_ITEM", "This item is not a plantable crop")
            if item.season not in {"all", self.world.state(now).current_season}:
                raise AppError(
                    "OUT_OF_SEASON", "This crop cannot be planted in the current season"
                )
            if settings.farm_consume_inventory:
                self.inventory.remove_internal(player_id, item.item_code)
            tile = tile or self.repo.create(world.id, request.x, request.y)
            tile.is_tilled = (
                True  # Old client has no till request; plant may till implicitly.
            )
            tile.crop_item_code = item.item_code
            tile.item = item
            tile.planted_at = tile.last_growth_update_at = now
            tile.growth_progress_seconds, tile.growth_stage = 0.0, 0
            tile.is_watered, tile.watered_at = False, None
            if item.xp_reward:
                self.economy.gain_internal(player_id, item.xp_reward)
            self.db.flush()
            result = PlantResponse(plot=tile_response(tile, state, now))
        return result

    def water(self, player_id, tile_id, now=None):
        now = now or utcnow()
        with transaction(self.db):
            self.players.lock(player_id)
            tile, state = self._owned(player_id, tile_id), self.world.raw_state()
            if not tile.crop_item_code:
                raise AppError("FARM_EMPTY", "There is no crop to water")
            self._persist_growth(tile, state, now)
            if tile.growth_stage == 3:
                raise AppError("FARM_READY", "This crop is ready for harvest")
            if tile.is_watered:
                raise AppError(
                    "FARM_ALREADY_WATERED",
                    "This growth stage has already been watered",
                    409,
                )
            tile.is_watered, tile.watered_at = True, now
            self.db.flush()
            result = tile_response(tile, state, now)
        return result

    def harvest(self, player_id, tile_id, now=None):
        now = now or utcnow()
        with transaction(self.db):
            self.players.lock(player_id)
            tile, state = self._owned(player_id, tile_id), self.world.raw_state()
            if not tile.crop_item_code:
                raise AppError(
                    "FARM_EMPTY",
                    "This crop was already harvested or the tile is empty",
                    409,
                )
            self._persist_growth(tile, state, now)
            if tile.growth_stage < 3:
                raise AppError("FARM_NOT_READY", "This crop is not fully grown")
            code, xp_reward = tile.crop_item_code, tile.item.xp_reward
            # Clear first so injected reward failures test rollback of farm state too.
            tile.crop_item_code, tile.item = None, None
            tile.planted_at = tile.last_growth_update_at = tile.watered_at = None
            tile.growth_progress_seconds, tile.growth_stage, tile.is_watered = (
                0.0,
                0,
                False,
            )
            self.db.flush()
            self.inventory.add_internal(player_id, code)
            if xp_reward:
                self.economy.gain_internal(player_id, xp_reward)
            self.db.flush()
            result = HarvestResponse(
                plot=tile_response(tile, state, now),
                item_code=code,
                crop_type=code,
                quantity=1,
            )
        return result
