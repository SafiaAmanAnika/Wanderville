import os
from pathlib import Path
import sys

from fastapi.testclient import TestClient

TEST_DB_PATH = Path(__file__).with_name("test_auth_deps.db")
if TEST_DB_PATH.exists():
    TEST_DB_PATH.unlink()
os.environ["DATABASE_URL"] = f"sqlite:///{TEST_DB_PATH.as_posix()}"
os.environ["JWT_SECRET_KEY"] = "test-secret-key"
os.environ["ACCESS_TOKEN_EXPIRE_MINUTES"] = "60"

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import main as _main  # noqa: E402
from app.database import Base, engine  # noqa: E402
import app.models.player  # noqa: F401, E402


Base.metadata.create_all(bind=engine)

client = TestClient(_main.app)


def test_me_without_token_returns_401():
    r = client.get("/auth/me")
    assert r.status_code == 401


def test_me_with_invalid_token_returns_401():
    r = client.get("/auth/me", headers={"Authorization": "Bearer invalid-token-here"})
    assert r.status_code == 401


def test_me_with_valid_token_returns_200():
    client.post(
        "/auth/signup",
        json={"username": "deptest", "password": "password123", "display_name": "Dep Test"},
    )
    r = client.post(
        "/auth/login",
        json={"username": "deptest", "password": "password123"},
    )
    token = r.json()["data"]["token"]
    r = client.get("/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert r.status_code == 200
    assert r.json()["data"]["username"] == "deptest"


def test_position_fields_in_player_response():
    client.post(
        "/auth/signup",
        json={"username": "postest", "password": "password123", "display_name": "Pos Test"},
    )
    r = client.post(
        "/auth/login",
        json={"username": "postest", "password": "password123"},
    )
    token = r.json()["data"]["token"]
    r = client.get("/auth/me", headers={"Authorization": f"Bearer {token}"})
    data = r.json()["data"]
    assert "position_x" in data
    assert "position_y" in data
    assert data["position_x"] == 0
    assert data["position_y"] == 0
