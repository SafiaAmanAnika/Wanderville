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
os.environ["DISABLE_RATE_LIMIT"] = "1"

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import main as _main  # noqa: E402
from app.database import Base, engine  # noqa: E402
import app.models.player  # noqa: F401, E402
import app.models.refresh_token  # noqa: F401, E402


Base.metadata.create_all(bind=engine)

client = TestClient(_main.app)


def _signup_and_verify_and_login(username="depuser", email="dep@example.com", password="Secret123!"):
    client.post(
        "/auth/signup",
        json={"username": username, "email": email, "password": password, "display_name": username},
    )
    from app.database import SessionLocal
    from app.models.player import Player

    db = SessionLocal()
    player = db.query(Player).filter(Player.username == username).first()
    player.email_verified = True
    player.is_active = True
    db.commit()
    db.close()

    r = client.post("/auth/login", json={"username": username, "password": password})
    return r.json()["data"]["access_token"]


def test_me_with_invalid_token_returns_401():
    r = client.get("/auth/me", headers={"Authorization": "Bearer invalid-token-here"})
    assert r.status_code == 401


def test_position_fields_in_player_response():
    _signup_and_verify_and_login(username="postest", email="pos@example.com")
    from app.database import SessionLocal
    from app.models.player import Player

    db = SessionLocal()
    player = db.query(Player).filter(Player.username == "postest").first()
    token = None
    db.close()

    r = client.post("/auth/login", json={"username": "postest", "password": "Secret123!"})
    token = r.json()["data"]["access_token"]

    r = client.get("/auth/me", headers={"Authorization": f"Bearer {token}"})
    data = r.json()["data"]
    assert "position_x" in data
    assert "position_y" in data
    assert data["position_x"] == 0
    assert data["position_y"] == 0


def test_me_without_token_returns_401():
    r = client.get("/auth/me")
    assert r.status_code == 401


def test_inactive_account_cannot_access_me():
    client.post(
        "/auth/signup",
        json={"username": "inactive", "email": "inactive@example.com", "password": "Secret123!", "display_name": "Inactive"},
    )
    from app.database import SessionLocal
    from app.models.player import Player

    db = SessionLocal()
    player = db.query(Player).filter(Player.username == "inactive").first()
    player.email_verified = True
    player.is_active = True
    db.commit()
    db.close()

    r = client.post("/auth/login", json={"username": "inactive", "password": "Secret123!"})
    token = r.json()["data"]["access_token"]

    db = SessionLocal()
    player = db.query(Player).filter(Player.username == "inactive").first()
    player.is_active = False
    db.commit()
    db.close()

    r = client.get("/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert r.status_code == 403
