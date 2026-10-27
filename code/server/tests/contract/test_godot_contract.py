import re
from pathlib import Path

import pytest

from app.core.progression import HARVEST_XP, LEVEL_AURA_REWARDS
from app.main import app
from app.modules.inventory.schemas import ItemRequest
from app.modules.inventory.service import InventoryService


def test_all_apiclient_routes_exist():
    api = Path(__file__).resolve().parents[3] / "client/autoloads/APIClient.gd"
    requests = re.findall(
        r'HTTPClient.METHOD_(GET|POST|PUT),\s*"([^"?]+)', api.read_text()
    )
    assert len(requests) >= 23  # Extensions must not remove the original contract.
    routes = {
        (method, route.path)
        for route in app.routes
        for method in getattr(route, "methods", [])
    }
    def matches(method, path):
        for server_method, server_path in routes:
            pattern = re.sub(r"\{[^}]+\}", r"[^/]+", server_path)
            if method == server_method and re.fullmatch(pattern, path):
                return True
        return False

    assert all(matches(method, path) for method, path in requests), [
        (method, path) for method, path in requests if not matches(method, path)
    ]



def test_every_client_screen_calls_a_real_route():
    """Screens outside APIClient.gd build their own URLs, often across a line
    break or with a format argument ("/market/%d/listings" % shop_id). A typo in
    any of them must fail here rather than ship as a 404."""
    client_dir = Path(__file__).resolve().parents[3] / "client"
    call = re.compile(r'HTTPClient\.METHOD_(\w+),\s*"(/[^"]*)"(\s*\+)?')
    routes = [
        (method, route.path, re.sub(r"\{[^}]+\}", "[^/]+", route.path))
        for route in app.routes
        for method in getattr(route, "methods", [])
    ]
    calls, missing = [], []
    for script in sorted(client_dir.glob("**/*.gd")):
        if "tests" in script.relative_to(client_dir).parts:
            continue
        for method, path, concatenated in call.findall(script.read_text()):
            path = re.sub(r"%[ds]", "1", path.split("?")[0])
            calls.append(path)
            # "/shop/" + action names only a prefix; some route must extend it.
            found = any(
                method == server_method and (
                    server_path.startswith(path) if concatenated
                    else re.fullmatch(pattern, path)
                )
                for server_method, server_path, pattern in routes
            )
            if not found:
                missing.append((script.relative_to(client_dir).as_posix(), method, path))
    assert "/market/1/listings" in calls and "/market/buy" in calls, calls
    assert not missing, missing

def test_login_player_and_token_shape(client, account):
    user = account()
    assert {
        "access_token",
        "refresh_token",
        "token_type",
        "player",
    } <= user.tokens.keys()
    assert {
        "id",
        "username",
        "display_name",
        "email",
        "position_x",
        "position_y",
    } <= user.tokens["player"].keys()
    assert user.tokens["token_type"] == "bearer"
    response = client.get("/auth/me", headers=user.headers)
    assert response.json()["data"]["id"] == user.id
    assert "hashed_password" not in response.text


def test_inventory_exact_godot_payload(client, account):
    user = account()
    assert client.get("/inventory/", headers=user.headers).json()["data"]["items"] == []
    added = client.post(
        "/inventory/add",
        headers=user.headers,
        json={"item_code": "wheat", "quantity": 3, "location": "inventory"},
    )
    assert added.status_code == 200, added.text
    data = client.get("/inventory/", headers=user.headers).json()["data"]
    assert data["items"][0]["item_code"] == "wheat"
    assert data["items"][0]["quantity"] == 3
    assert data["total_items"] == 1 and data["total_quantity"] == 3
    assert (
        client.post(
            "/inventory/remove",
            headers=user.headers,
            json={"item_code": "wheat", "quantity": 1},
        ).status_code
        == 200
    )
    assert (
        len(client.get("/inventory/catalog", headers=user.headers).json()["data"]) == 51
    )


def test_economy_exact_godot_payloads(client, account):
    user = account()
    assert (
        client.get("/economy/", headers=user.headers).json()["data"]["taka_balance"]
        == 10
    )
    earned = client.post(
        "/economy/earn",
        headers=user.headers,
        json={"amount": 100, "currency_type": "taka", "description": "test"},
    )
    assert earned.json()["data"]["taka_balance"] == 110
    spent = client.post(
        "/economy/spend",
        headers=user.headers,
        json={"amount": 20, "currency_type": "taka", "description": "test"},
    )
    assert spent.json()["data"]["aura_balance"] == 90
    gained = client.post(
        "/economy/xp/gain",
        headers=user.headers,
        json={"xp_amount": 110, "source": "test"},
    )
    assert gained.json()["data"]["level"] == 2
    assert (
        client.get("/economy/xp", headers=user.headers).json()["data"]["total_xp"]
        == 110
    )


def test_progression_payload_is_frozen_for_the_client(client, account):
    """The HUD, seed picker and store all read these keys; do not rename them."""
    user = account()
    fresh = client.get("/economy/xp", headers=user.headers).json()["data"]
    assert set(fresh) == {
        "player_id",
        "current_xp",
        "total_xp",
        "level",
        "xp_to_next_level",
        "xp_span",
        "xp_floor",
        "title",
        "max_level",
        "next_title",
        "next_title_level",
        "slot_increment",
        "slot_capacity",
        "rewards",
        "unlocked_items",
    }
    assert fresh["level"] == 1
    assert fresh["title"] == "Villager"
    assert fresh["max_level"] is False
    assert fresh["xp_floor"] == 0
    assert fresh["xp_to_next_level"] == 80
    assert fresh["xp_span"] == 80
    assert fresh["slot_increment"] == 3
    assert fresh["slot_capacity"] == 33
    # Villager is shared by levels 1 and 2, so the previewed title is the next
    # genuinely different one, at level 3.
    assert fresh["next_title"] == "Farmer"
    assert fresh["next_title_level"] == 3
    assert fresh["rewards"] == []

    crossed = client.post(
        "/economy/xp/gain",
        headers=user.headers,
        json={"xp_amount": 180, "source": "test"},
    ).json()["data"]
    # Level 2 and level 3 crossed at once, so the level 2 payout is reported
    # once and levels without a reward are not announced at all.
    assert crossed["level"] == 3
    assert crossed["title"] == "Farmer"
    assert crossed["slot_capacity"] == 39
    assert crossed["rewards"] == [
        {"level": 2, "aura": LEVEL_AURA_REWARDS[2], "title": "Villager"}
    ]

    top = client.post(
        "/economy/xp/gain",
        headers=user.headers,
        json={"xp_amount": 5000, "source": "test"},
    ).json()["data"]
    assert top["level"] == 10 and top["max_level"] is True
    assert top["xp_to_next_level"] == 0
    assert top["slot_capacity"] == 76
    # Level 2 was already paid on the way up, so only level 10 is new here.
    assert top["rewards"] == [
        {"level": 10, "aura": LEVEL_AURA_REWARDS[10], "title": "Landkeeper"}
    ]
    history = client.get("/economy/xp", headers=user.headers).json()["data"]["rewards"]
    assert history == [
        {"level": 2, "aura": LEVEL_AURA_REWARDS[2], "title": "Villager"},
        {"level": 10, "aura": LEVEL_AURA_REWARDS[10], "title": "Landkeeper"},
    ]


def test_inventory_capacity_payload_is_frozen_for_the_client(client, account, db):
    user = account()
    data = client.get("/inventory/", headers=user.headers).json()["data"]
    assert set(data) == {
        "items",
        "total_items",
        "total_quantity",
        "capacity",
        "used_slots",
        "base_capacity",
        "level_slots",
        "max_stack",
    }
    assert data["capacity"] == data["base_capacity"] + data["level_slots"] == 33
    assert data["used_slots"] == 0
    InventoryService(db).add_compatibility(
        user.id, ItemRequest(item_code="wheat", quantity=250)
    )
    data = client.get("/inventory/", headers=user.headers).json()["data"]
    assert data["total_items"] == 3 and data["total_quantity"] == 250
    assert data["used_slots"] == 3 and data["capacity"] == 33
    row = data["items"][0]
    # The seed picker reads required_level, harvest_code and harvest_category
    # straight off each row, so these names are part of the client contract.
    assert set(row) == {
        "id",
        "player_id",
        "item_code",
        "quantity",
        "slot_index",
        "location",
        "item_type",
        "partition",
        "required_level",
        "harvest_code",
        "harvest_category",
        "harvest_xp",
        "item",
        "max_stack",
        "created_at",
        "updated_at",
    }
    assert row["required_level"] == 1
    assert row["harvest_category"] == "common"
    assert row["harvest_xp"] == HARVEST_XP["common"]
    assert row["harvest_code"] is None
    assert row["max_stack"] == 99
    # A level up widens the same pool rather than resetting it.
    client.post(
        "/economy/xp/gain", headers=user.headers, json={"xp_amount": 5000}
    )
    grown = client.get("/inventory/", headers=user.headers).json()["data"]
    assert grown["capacity"] == 76
    assert grown["used_slots"] == 3


def test_seed_picker_payload_carries_unlock_and_harvest(client, account):
    user = account()
    rows = {
        row["item_code"]: row
        for row in client.get("/shop", headers=user.headers).json()["data"]["items"]
    }
    for code, level in (("wheat_seed", 1), ("potato_seed", 4), ("moonflower_seed", 8)):
        assert rows[code]["required_level"] == level
        assert rows[code]["harvest_code"] == code.removesuffix("_seed")
        assert rows[code]["harvest_category"] is None
    assert rows["basic_rod"]["required_level"] == 5

    catalog = {
        row["item_code"]: row
        for row in client.get(
            "/inventory/catalog", headers=user.headers
        ).json()["data"]
    }
    for code, category in (
        ("wheat", "common"),
        ("sugarcane", "common"),
        ("potato", "seasonal"),
        ("apple", "seasonal"),
        ("moonflower", "rare"),
        ("ancient_grain", "magical"),
    ):
        assert catalog[code]["harvest_category"] == category
        assert catalog[code]["harvest_xp"] == HARVEST_XP[category]
    assert catalog["wheat_seed"]["harvest_category"] is None
    # Fish are caught, not harvested, so they carry no crop category at all.
    assert catalog["river_carp"]["harvest_category"] is None


def test_world_and_farm_exact_godot_payloads(client, account):
    user = account()
    assert (
        client.get("/world/me", headers=user.headers).json()["data"]["owner_id"]
        == user.id
    )
    state = client.get("/world/state", headers=user.headers).json()["data"]
    assert state["current_season"] in {"summer", "autumn", "winter", "spring"}
    assert client.get("/farm/plots", headers=user.headers).json()["data"]["plots"] == []
    client.post(
        "/inventory/add",
        headers=user.headers,
        json={"item_code": "wheat", "quantity": 1},
    )
    planted = client.post(
        "/farm/plant", headers=user.headers, json={"x": 3, "y": 4, "item_code": "wheat"}
    )
    assert planted.status_code == 200, planted.text
    plot = planted.json()["data"]["plot"]
    assert plot["item_code"] == "wheat"
    assert (
        client.post(
            "/farm/water", headers=user.headers, json={"plot_id": plot["id"]}
        ).status_code
        == 200
    )
    early = client.post(
        "/farm/harvest", headers=user.headers, json={"plot_id": plot["id"]}
    )
    assert early.json()["error"] == "FARM_NOT_READY"


@pytest.mark.parametrize(
    "path",
    [
        "/auth/me",
        "/inventory/",
        "/inventory/catalog",
        "/economy/",
        "/economy/xp",
        "/world/me",
        "/world/state",
        "/farm/plots",
    ],
)
def test_protected_reads_have_standard_errors(client, path):
    response = client.get(path)
    assert response.status_code == 401
    assert response.json() == {
        "success": False,
        "error": "INVALID_TOKEN",
        "message": "Invalid or expired token",
    }


def test_validation_never_echoes_password(client):
    result = client.post(
        "/auth/signup",
        json={"username": "x", "email": "bad", "password": "SecretThatMustNotBeEchoed"},
    )
    assert result.status_code == 422
    assert result.json()["success"] is False
    assert "SecretThatMustNotBeEchoed" not in result.text


def test_health_docs_openapi(client):
    assert client.get("/health").json()["data"] == {"status": "ok"}
    assert client.get("/docs").status_code == 200
    assert client.get("/openapi.json").status_code == 200
