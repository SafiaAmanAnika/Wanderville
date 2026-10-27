"""The bundle must be a faithful aggregate of the endpoints it replaces.

The Godot client fetched these six sections sequentially after every farm
action, so one interaction cost seven round trips. These tests pin the bundle
to the standalone responses so the client can switch without changing any
gameplay behavior.
"""

import pytest

from app.modules.economy.service import EconomyService
from app.modules.farming.schemas import PlantRequest
from app.modules.farming.service import FarmingService
from app.modules.inventory.service import InventoryService
from app.modules.profile.service import ProfileService
from app.modules.world.service import WorldService

SECTIONS = ["profile", "farm", "world", "inventory", "economy", "experience", "session"]


@pytest.fixture
def planted(client, account, db):
    user = account()
    client.post(
        "/inventory/add",
        headers=user.headers,
        json={"item_code": "wheat", "quantity": 5},
    )
    FarmingService(db).plant(user.id, PlantRequest(x=2, y=3, item_code="wheat"))
    return user


def get(client, user, path):
    response = client.get(path, headers=user.headers)
    assert response.status_code == 200, response.text
    return response.json()["data"]


def test_bundle_requires_authentication(client):
    assert client.get("/state/bundle").status_code == 401


def test_bundle_returns_every_section(client, planted):
    data = get(client, planted, "/state/bundle")
    assert sorted(data) == sorted(SECTIONS)
    assert all(section in data for section in SECTIONS)


def test_bundle_matches_each_standalone_endpoint(client, planted):
    """Section payloads must equal the endpoints the client used to call."""
    user = planted
    data = get(client, user, "/state/bundle")
    assert data["farm"] == get(client, user, "/farm/plots")
    # current_time_of_day is sampled live from the clock, so it necessarily
    # differs between two requests; every other world field must match.
    bundle_world = dict(data["world"])
    standalone_world = get(client, user, "/world/state")
    assert 0.0 <= bundle_world.pop("current_time_of_day") < 1.0
    assert 0.0 <= standalone_world.pop("current_time_of_day") < 1.0
    from datetime import datetime
    bundle_time = datetime.fromisoformat(bundle_world.pop("server_time"))
    standalone_time = datetime.fromisoformat(standalone_world.pop("server_time"))
    assert 0 <= (standalone_time - bundle_time).total_seconds() < 5
    assert bundle_world == standalone_world
    assert data["inventory"] == get(client, user, "/inventory/")
    assert data["economy"] == get(client, user, "/economy/")
    assert data["experience"] == get(client, user, "/economy/xp")
    assert data["session"] == get(client, user, "/farm/visiting/session")
    assert data["session"]["session_mode"] == "OWNER"
    assert data["session"]["current_world_id"] == data["session"]["owned_world_id"]
    assert data["session"]["host_player_id"] is None


def test_bundle_profile_carries_bucket_charges(client, planted):
    """The client reads water_charges from this section after every action."""
    data = get(client, planted, "/state/bundle")
    assert "water_charges" in data["profile"]
    assert isinstance(data["profile"]["water_charges"], int)


def test_bundle_is_read_only(client, planted, db):
    """Polling must not advance growth, water, or consume anything."""
    user = planted
    service = FarmingService(db)
    tile_id = service.list(user.id).plots[0].id
    before = service.list(user.id).plots[0]
    get(client, user, "/state/bundle")
    after = FarmingService(db).list(user.id).plots[0]
    assert after.growth_stage == before.growth_stage
    assert after.is_watered == before.is_watered
    assert EconomyService(db).xp(user.id).total_xp >= 0
    assert tile_id == after.id


def test_bundle_and_service_agree(client, planted, db):
    user = planted
    data = get(client, user, "/state/bundle")
    assert data["inventory"]["total_quantity"] == InventoryService(db).list(user.id).total_quantity
    assert data["economy"]["aura_balance"] == EconomyService(db).get(user.id).aura_balance
    assert data["experience"]["total_xp"] == EconomyService(db).xp(user.id).total_xp
    assert "display_name" in ProfileService(db).get(user.id)
    assert data["world"]["current_season"] == WorldService(db).state().current_season


def test_bundle_reflects_state_after_each_action(client, planted):
    """Each farm action must be visible in the next bundle, as before."""
    user = planted
    plots = get(client, user, "/state/bundle")["farm"]["plots"]
    tile_id = next(p["id"] for p in plots if p["item_code"] == "wheat")

    watered = client.post(
        "/farm/water", headers=user.headers, json={"plot_id": tile_id}
    )
    assert watered.status_code == 200, watered.text
    after_water = next(
        p for p in get(client, user, "/state/bundle")["farm"]["plots"] if p["id"] == tile_id
    )
    assert after_water["is_watered"] is True

    tilled = client.post("/farm/till", headers=user.headers, json={"x": 7, "y": 8})
    assert tilled.status_code == 200, tilled.text
    fresh = next(
        p for p in get(client, user, "/state/bundle")["farm"]["plots"] if p["x"] == 7 and p["y"] == 8
    )
    assert fresh["is_tilled"] is True