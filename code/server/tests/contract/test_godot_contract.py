import re
from pathlib import Path

import pytest

from app.main import app


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
