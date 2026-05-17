import os
from pathlib import Path
import sys

from fastapi.testclient import TestClient

TEST_DB_PATH = Path(__file__).with_name("test_world.db")
if TEST_DB_PATH.exists():
    TEST_DB_PATH.unlink()
os.environ["DATABASE_URL"] = f"sqlite:///{TEST_DB_PATH.as_posix()}"
os.environ["JWT_SECRET_KEY"] = "test-secret-key"
os.environ["ACCESS_TOKEN_EXPIRE_MINUTES"] = "60"
os.environ["DISABLE_RATE_LIMIT"] = "1"

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import main as _main  # noqa: E402
from app.database import Base, engine  # noqa: E402
import app.models.player  # noqa: F401, E402
import app.models.world  # noqa: F401, E402


Base.metadata.create_all(bind=engine)

client = TestClient(_main.app)


def _signup_and_login(username="worlduser", password="secret123", display_name="World User"):
    """Helper: signup then login, return token string."""
    client.post(
        "/auth/signup",
        json={"username": username, "password": password, "display_name": display_name},
    )
    r = client.post("/auth/login", json={"username": username, "password": password})
    return r.json()["data"]["token"]


# ── GET /world/me ──────────────────────────────────────────────────────────

def test_get_world_me_without_token_returns_401():
    r = client.get("/world/me")
    assert r.status_code == 401


def test_get_world_me_auto_creates_world():
    token = _signup_and_login("autocreate", "secret123", "Auto Create")
    r = client.get("/world/me", headers={"Authorization": f"Bearer {token}"})
    assert r.status_code == 200
    body = r.json()
    assert body["success"] is True
    assert body["data"]["name"] == "My World"
    assert body["data"]["tiles"] == {}
    assert "id" in body["data"]
    assert "owner_id" in body["data"]
    assert "created_at" in body["data"]


def test_get_world_me_is_idempotent():
    """Calling /world/me multiple times returns the same world."""
    token = _signup_and_login("idempotent", "secret123", "Idempotent")
    r1 = client.get("/world/me", headers={"Authorization": f"Bearer {token}"})
    r2 = client.get("/world/me", headers={"Authorization": f"Bearer {token}"})
    assert r1.json()["data"]["id"] == r2.json()["data"]["id"]


# ── PUT /world/tiles ───────────────────────────────────────────────────────

def test_update_tiles_full_replacement():
    token = _signup_and_login("tileuser", "secret123", "Tile User")
    client.get("/world/me", headers={"Authorization": f"Bearer {token}"})

    tiles = {"0,0": "grass", "1,0": "dirt", "0,1": "water"}
    r = client.put(
        "/world/tiles",
        headers={"Authorization": f"Bearer {token}"},
        json={"tiles": tiles},
    )
    assert r.status_code == 200
    body = r.json()
    assert body["success"] is True
    assert body["data"]["tiles"] == tiles
    assert body["message"] == "Tiles updated"


def test_update_tiles_replaces_previous_data():
    """Second PUT /world/tiles should fully replace, not merge."""
    token = _signup_and_login("replaceuser", "secret123", "Replace User")
    client.get("/world/me", headers={"Authorization": f"Bearer {token}"})

    client.put(
        "/world/tiles",
        headers={"Authorization": f"Bearer {token}"},
        json={"tiles": {"0,0": "grass", "1,0": "dirt"}},
    )
    r = client.put(
        "/world/tiles",
        headers={"Authorization": f"Bearer {token}"},
        json={"tiles": {"5,5": "stone"}},
    )
    assert r.json()["data"]["tiles"] == {"5,5": "stone"}


def test_update_tiles_without_token_returns_401():
    r = client.put("/world/tiles", json={"tiles": {"0,0": "grass"}})
    assert r.status_code == 401


def test_update_tiles_with_empty_dict():
    token = _signup_and_login("emptyuser", "secret123", "Empty User")
    client.get("/world/me", headers={"Authorization": f"Bearer {token}"})

    r = client.put(
        "/world/tiles",
        headers={"Authorization": f"Bearer {token}"},
        json={"tiles": {}},
    )
    assert r.status_code == 200
    assert r.json()["data"]["tiles"] == {}


# ── PUT /world/tile ────────────────────────────────────────────────────────

def test_update_single_tile_adds_new_tile():
    token = _signup_and_login("singletile", "secret123", "Single Tile")
    client.get("/world/me", headers={"Authorization": f"Bearer {token}"})

    r = client.put(
        "/world/tile",
        headers={"Authorization": f"Bearer {token}"},
        json={"x": 3, "y": 4, "tile_type": "grass"},
    )
    assert r.status_code == 200
    body = r.json()
    assert body["success"] is True
    assert body["data"]["tiles"]["3,4"] == "grass"
    assert body["message"] == "Tile updated"


def test_update_single_tile_overwrites_existing():
    token = _signup_and_login("overwrite", "secret123", "Overwrite")
    client.get("/world/me", headers={"Authorization": f"Bearer {token}"})

    client.put(
        "/world/tile",
        headers={"Authorization": f"Bearer {token}"},
        json={"x": 0, "y": 0, "tile_type": "grass"},
    )
    r = client.put(
        "/world/tile",
        headers={"Authorization": f"Bearer {token}"},
        json={"x": 0, "y": 0, "tile_type": "water"},
    )
    assert r.json()["data"]["tiles"]["0,0"] == "water"


def test_update_single_tile_preserves_other_tiles():
    """Updating one tile should not remove others."""
    token = _signup_and_login("preserve", "secret123", "Preserve")
    client.get("/world/me", headers={"Authorization": f"Bearer {token}"})

    client.put(
        "/world/tiles",
        headers={"Authorization": f"Bearer {token}"},
        json={"tiles": {"0,0": "grass", "1,1": "dirt"}},
    )
    r = client.put(
        "/world/tile",
        headers={"Authorization": f"Bearer {token}"},
        json={"x": 2, "y": 2, "tile_type": "stone"},
    )
    tiles = r.json()["data"]["tiles"]
    assert tiles["0,0"] == "grass"
    assert tiles["1,1"] == "dirt"
    assert tiles["2,2"] == "stone"


def test_update_single_tile_without_token_returns_401():
    r = client.put("/world/tile", json={"x": 0, "y": 0, "tile_type": "grass"})
    assert r.status_code == 401


def test_update_single_tile_negative_coordinates():
    """Negative coordinates should work as valid tile keys."""
    token = _signup_and_login("negcoord", "secret123", "Neg Coord")
    client.get("/world/me", headers={"Authorization": f"Bearer {token}"})

    r = client.put(
        "/world/tile",
        headers={"Authorization": f"Bearer {token}"},
        json={"x": -1, "y": -2, "tile_type": "sand"},
    )
    assert r.status_code == 200
    assert r.json()["data"]["tiles"]["-1,-2"] == "sand"


# ── Cross-user isolation ──────────────────────────────────────────────────

def test_users_have_separate_worlds():
    """Two users should not see or modify each other's tiles."""
    token_a = _signup_and_login("alice_world", "secret123", "Alice")
    token_b = _signup_and_login("bob_world", "secret123", "Bob")

    client.get("/world/me", headers={"Authorization": f"Bearer {token_a}"})
    client.get("/world/me", headers={"Authorization": f"Bearer {token_b}"})

    client.put(
        "/world/tile",
        headers={"Authorization": f"Bearer {token_a}"},
        json={"x": 0, "y": 0, "tile_type": "grass"},
    )

    r_b = client.get("/world/me", headers={"Authorization": f"Bearer {token_b}"})
    assert r_b.json()["data"]["tiles"] == {}



