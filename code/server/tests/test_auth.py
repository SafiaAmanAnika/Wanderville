import os
from pathlib import Path
import sys

from fastapi.testclient import TestClient


# Ensure settings are loaded from environment for tests (no real .env needed).
TEST_DB_PATH = Path(__file__).with_name("test_auth.db")
if TEST_DB_PATH.exists():
    TEST_DB_PATH.unlink()
os.environ.setdefault("DATABASE_URL", f"sqlite:///{TEST_DB_PATH.as_posix()}")
os.environ.setdefault("JWT_SECRET_KEY", "test-secret-key")
os.environ.setdefault("ACCESS_TOKEN_EXPIRE_MINUTES", "60")

# Ensure `code/server` is importable as the root module path.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from main import app  # noqa: E402

from app.database import Base, engine  # noqa: E402
import app.models.player as _player_model  # noqa: F401, E402


Base.metadata.create_all(bind=engine)


client = TestClient(app)


def test_signup_and_login_and_me_flow():
    # Signup
    r = client.post(
        "/auth/signup",
        json={"username": "testuser", "password": "secret123", "display_name": "Test User"},
    )
    assert r.status_code == 200
    body = r.json()
    assert body["success"] is True
    assert body["data"]["username"] == "testuser"
    assert "hashed_password" not in body["data"]

    # Duplicate signup
    r2 = client.post(
        "/auth/signup",
        json={"username": "testuser", "password": "secret123", "display_name": "Test User"},
    )
    assert r2.status_code == 400
    body2 = r2.json()
    assert body2["success"] is False
    assert body2["error"] == "USERNAME_TAKEN"

    # Login
    r3 = client.post("/auth/login", json={"username": "testuser", "password": "secret123"})
    assert r3.status_code == 200
    body3 = r3.json()
    assert body3["success"] is True
    token = body3["data"]["token"]
    assert isinstance(token, str) and token

    # Wrong password
    r4 = client.post("/auth/login", json={"username": "testuser", "password": "wrongpass"})
    assert r4.status_code == 401
    body4 = r4.json()
    assert body4["success"] is False
    assert body4["error"] == "INVALID_CREDENTIALS"

    # /auth/me requires token
    r5 = client.get("/auth/me")
    assert r5.status_code == 401

    # /auth/me with token
    r6 = client.get("/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert r6.status_code == 200
    body6 = r6.json()
    assert body6["success"] is True
    assert body6["data"]["username"] == "testuser"
