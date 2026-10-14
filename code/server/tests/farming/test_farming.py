from datetime import timedelta

import pytest
from sqlalchemy import func, select

from app.core.clock import utcnow
from app.core.exceptions import AppError
from app.core.progression import (
    DEFAULT_PLANT_XP,
    FIRST_HARVEST_XP,
    HARVEST_XP,
)
from app.modules.economy.service import EconomyService
from app.modules.farming.models import FarmTile
from app.modules.farming.schemas import PlantRequest, TileRequest
from app.modules.farming.service import FarmingService
from app.modules.inventory.models import PlayerFirstHarvest
from app.modules.inventory.service import InventoryService
from app.modules.world.models import WorldState


@pytest.fixture
def farm(client, account, db):
    user = account()
    client.post(
        "/inventory/add",
        headers=user.headers,
        json={"item_code": "wheat", "quantity": 5},
    )
    service = FarmingService(db)
    start = utcnow()
    plot = service.plant(user.id, PlantRequest(x=3, y=4, item_code="wheat"), start).plot
    return user, service, plot.id, start


def grow(farm):
    user, service, tile_id, now = farm
    service.water(user.id, tile_id, now)
    now += timedelta(seconds=18)
    return now


def test_plant_validation_consumption_xp_and_ownership(farm, client, account, db):
    user, service, tile_id, now = farm
    assert InventoryService(db).list(user.id).total_quantity == 4
    # Planting pays the flat DEFAULT_PLANT_XP, not the crop's harvest value.
    assert EconomyService(db).xp(user.id).total_xp == DEFAULT_PLANT_XP
    with pytest.raises(AppError) as occupied:
        service.plant(user.id, PlantRequest(x=3, y=4, item_code="wheat"), now)
    assert occupied.value.code == "FARM_PLOT_OCCUPIED"
    for code, expected in [
        ("unknown", "INVALID_ITEM"),
        # Potato is a level 4 seasonal crop, so a level 1 player is stopped
        # by the level lock before the season is ever considered.
        ("potato", "LEVEL_internal"),
        ("paddy", "INSUFFICIENT_INVENTORY"),
    ]:
        with pytest.raises(AppError) as exc:
            service.plant(user.id, PlantRequest(x=4, y=4, item_code=code), now)
        assert exc.value.code == expected
    other = account("otherplayer")
    assert (
        client.post(
            "/farm/water", headers=other.headers, json={"plot_id": tile_id}
        ).status_code
        == 404
    )
    assert (
        client.post(
            "/farm/harvest", headers=other.headers, json={"plot_id": tile_id}
        ).status_code
        == 404
    )
    assert (
        client.post(
            "/farm/water", headers=user.headers, json={"plot_id": 999999}
        ).status_code
        == 404
    )
    assert (
        client.post(
            "/farm/plant",
            headers=user.headers,
            json={"x": -1, "y": 0, "item_code": "wheat"},
        ).status_code
        == 422
    )


def test_scene_crop_waits_for_water_then_grows_continuously(farm, db):
    user, service, tile_id, now = farm
    assert service.list(user.id, now + timedelta(days=2)).plots[0].growth_stage == 0
    watered = service.water(user.id, tile_id, now + timedelta(days=2))
    assert watered.growth_progress_seconds == 0
    with pytest.raises(AppError) as exc:
        service.water(user.id, tile_id, now + timedelta(days=2, seconds=1))
    assert exc.value.code == "FARM_ALREADY_WATERED"
    projected = service.list(user.id, now + timedelta(days=3)).plots[0]
    assert projected.ready and projected.visual_frame == 4
    assert projected.growth_progress_seconds == 18
    assert (
        service.list(user.id, now + timedelta(days=4)).plots[0].growth_progress_seconds
        == 18
    )
    assert not db.dirty  # GET projections do not write or commit.


def test_ready_harvest_rewards_reuse_and_double_harvest(farm, db):
    user, service, tile_id, start = farm
    with pytest.raises(AppError) as early:
        service.harvest(user.id, tile_id, start)
    assert early.value.code == "FARM_NOT_READY"
    now = grow(farm)
    assert service.list(user.id, now).plots[0].ready
    result = service.harvest(user.id, tile_id, now)
    assert result.item_code == "wheat" and result.quantity == 1
    assert result.plot.item_code is None and not result.plot.is_tilled
    assert InventoryService(db).list(user.id).total_quantity == 5
    # Wheat is a common crop (5 XP) and this is its first harvest (+15 once).
    assert EconomyService(db).xp(user.id).total_xp == (
        DEFAULT_PLANT_XP + HARVEST_XP["common"] + FIRST_HARVEST_XP
    )
    with pytest.raises(AppError) as again:
        service.harvest(user.id, tile_id, now)
    assert again.value.code == "FARM_EMPTY"
    service.till(user.id, TileRequest(x=3, y=4), now)
    replanted = service.plant(
        user.id, PlantRequest(x=3, y=4, crop_type="wheat"), now
    ).plot
    assert replanted.id == tile_id and replanted.growth_stage == 0
    assert len(db.scalars(select(FarmTile)).all()) == 1


def test_first_harvest_bonus_is_paid_once_per_species(farm, db):
    user, service, tile_id, now = farm

    def harvest(at):
        service.harvest(user.id, tile_id, at)
        return EconomyService(db).xp(user.id).total_xp

    def replant(at):
        return service.plant(
            user.id, PlantRequest(x=3, y=4, crop_type="wheat"), at
        ).plot

    now = grow(farm)
    first = harvest(now)
    # Wheat is a common crop, so this is plant XP + common XP + the once-only
    # first-harvest bonus for the species.
    assert first == DEFAULT_PLANT_XP + HARVEST_XP["common"] + FIRST_HARVEST_XP

    replant(now)
    now += timedelta(seconds=120)
    service.water(user.id, tile_id, now)
    now += timedelta(seconds=60)
    second = harvest(now)
    # The second harvest pays plant + common XP only; the bonus is spent once.
    assert second == first + DEFAULT_PLANT_XP + HARVEST_XP["common"]
    assert EconomyService(db).xp(user.id).level == 1
    assert (
        db.scalar(
            select(func.count())
            .select_from(PlayerFirstHarvest)
            .where(PlayerFirstHarvest.player_id == user.id)
        )
        == 1
    )


def test_harvest_reward_failure_rolls_back_everything(farm, db, monkeypatch):
    user, service, tile_id, _ = farm
    now = grow(farm)
    before_xp = EconomyService(db).xp(user.id).total_xp

    def fail(*args):
        raise RuntimeError("inventory reward failed")

    monkeypatch.setattr(InventoryService, "add_internal", fail)
    with pytest.raises(RuntimeError):
        service.harvest(user.id, tile_id, now)
    db.expire_all()
    assert db.get(FarmTile, tile_id).crop_item_code == "wheat"
    assert InventoryService(db).list(user.id).total_quantity == 4
    assert EconomyService(db).xp(user.id).total_xp == before_xp


def test_full_inventory_keeps_mature_crop_and_first_bonus_available(farm, db):
    from app.modules.inventory.models import ItemDefinition
    from app.modules.inventory.schemas import ItemRequest

    user, service, tile_id, _ = farm
    now = grow(farm)
    inventory = InventoryService(db)
    inventory.add_compatibility(user.id, ItemRequest(item_code="wheat", quantity=95))
    codes = [code for code in db.scalars(select(ItemDefinition.item_code)) if code != "wheat"]
    for code in codes[:inventory.capacity(user.id) - 1]:
        inventory.add_internal(user.id, code)
    db.commit()
    before_xp = EconomyService(db).xp(user.id).total_xp
    with pytest.raises(AppError) as failure:
        service.harvest(user.id, tile_id, now)
    assert failure.value.code == "INVENTORY_FULL"
    db.expire_all()
    assert service.list(user.id, now).plots[0].ready
    assert db.get(FarmTile, tile_id).crop_item_code == "wheat"
    assert db.get(PlayerFirstHarvest, (user.id, "wheat")) is None
    assert EconomyService(db).xp(user.id).total_xp == before_xp
    inventory.remove(user.id, ItemRequest(item_code="wheat", quantity=1))
    service.harvest(user.id, tile_id, now)
    assert inventory.repo.stack(user.id, "wheat").quantity == 99
    assert EconomyService(db).xp(user.id).total_xp == before_xp + 20


def test_season_changes_growth_speed(farm, db):
    user, service, tile_id, now = farm
    # Crops without a supplied Godot scene retain their catalog/season rules.
    from app.modules.inventory.models import ItemDefinition
    tile = db.get(FarmTile, tile_id)
    tile.crop_item_code = "corn"
    tile.item = db.scalar(select(ItemDefinition).where(ItemDefinition.item_code == "corn"))
    db.commit()
    service.water(user.id, tile_id, now)
    assert service.list(user.id, now + timedelta(seconds=4)).plots[
        0
    ].growth_progress_seconds == pytest.approx(5)
    state = db.get(WorldState, 1)
    state.current_season = "winter"
    db.commit()
    assert service.list(user.id, now + timedelta(seconds=4)).plots[
        0
    ].growth_progress_seconds == pytest.approx(3)


def test_relocate_moves_whole_tile(farm, db):
    from app.modules.farming.schemas import RelocateRequest, TileRequest

    user, service, plot_id, start = farm
    # crop + soil move together; old spot goes back to grass
    moved = service.relocate(user.id, RelocateRequest(plot_id=plot_id, x=5, y=5), start)
    assert moved["plot"].item_code == "wheat" and moved["plot"].is_tilled
    assert moved["source"].item_code is None and moved["source"].is_tilled is False
    # an empty soil tile can move onto grass ...
    soil = service.till(user.id, TileRequest(x=1, y=1), start)
    moved = service.relocate(user.id, RelocateRequest(plot_id=soil.id, x=2, y=2), start)
    assert moved["plot"].is_tilled and not moved["source"].is_tilled
    # ... but not onto other soil, and nothing can land on a crop
    service.till(user.id, TileRequest(x=7, y=7), start)
    with pytest.raises(AppError, match="already used"):
        service.relocate(user.id, RelocateRequest(plot_id=moved["plot"].id, x=7, y=7), start)
    with pytest.raises(AppError, match="already used"):
        service.relocate(user.id, RelocateRequest(plot_id=moved["plot"].id, x=5, y=5), start)
