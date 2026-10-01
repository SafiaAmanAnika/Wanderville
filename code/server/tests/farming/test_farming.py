from datetime import timedelta

import pytest
from sqlalchemy import select

from app.core.clock import utcnow
from app.core.exceptions import AppError
from app.modules.economy.service import EconomyService
from app.modules.farming.models import FarmTile
from app.modules.farming.schemas import PlantRequest
from app.modules.farming.service import FarmingService
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
    for _ in range(3):
        service.water(user.id, tile_id, now)
        now += timedelta(seconds=60)
    return now


def test_plant_validation_consumption_xp_and_ownership(farm, client, account, db):
    user, service, tile_id, now = farm
    assert InventoryService(db).list(user.id).total_quantity == 4
    assert EconomyService(db).xp(user.id).total_xp == 5
    with pytest.raises(AppError) as occupied:
        service.plant(user.id, PlantRequest(x=3, y=4, item_code="wheat"), now)
    assert occupied.value.code == "FARM_PLOT_OCCUPIED"
    for code, expected in [
        ("unknown", "INVALID_ITEM"),
        ("potato", "OUT_OF_SEASON"),
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


def test_water_once_per_stage_and_dry_growth_pause(farm, db):
    user, service, tile_id, now = farm
    assert service.list(user.id, now + timedelta(days=2)).plots[0].growth_stage == 0
    watered = service.water(user.id, tile_id, now + timedelta(days=2))
    assert watered.growth_progress_seconds == 0
    with pytest.raises(AppError) as exc:
        service.water(user.id, tile_id, now + timedelta(days=2, seconds=1))
    assert exc.value.code == "FARM_ALREADY_WATERED"
    projected = service.list(user.id, now + timedelta(days=3)).plots[0]
    assert projected.growth_stage == 1 and not projected.is_watered
    assert projected.growth_progress_seconds == 15
    assert (
        service.list(user.id, now + timedelta(days=4)).plots[0].growth_progress_seconds
        == 15
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
    assert result.plot.item_code is None and result.plot.is_tilled
    assert InventoryService(db).list(user.id).total_quantity == 5
    assert EconomyService(db).xp(user.id).total_xp == 10
    with pytest.raises(AppError) as again:
        service.harvest(user.id, tile_id, now)
    assert again.value.code == "FARM_EMPTY"
    replanted = service.plant(
        user.id, PlantRequest(x=3, y=4, crop_type="wheat"), now
    ).plot
    assert replanted.id == tile_id and replanted.growth_stage == 0
    assert len(db.scalars(select(FarmTile)).all()) == 1


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


def test_season_changes_growth_speed(farm, db):
    user, service, tile_id, now = farm
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
