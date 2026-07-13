import os
from pathlib import Path
import sys

from fastapi.testclient import TestClient


TEST_DB_PATH = Path(__file__).with_name("test_auth.db")
if TEST_DB_PATH.exists():
    TEST_DB_PATH.unlink()
os.environ.setdefault("DATABASE_URL", f"sqlite:///{TEST_DB_PATH.as_posix()}")
os.environ.setdefault("JWT_SECRET_KEY", "test-secret-key")
os.environ.setdefault("ACCESS_TOKEN_EXPIRE_MINUTES", "60")
os.environ.setdefault("DISABLE_RATE_LIMIT", "1")

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from main import app  # noqa: E402
from app.database import Base, engine  # noqa: E402
import app.models.player as _player_model  # noqa: F401, E402
import app.models.refresh_token as _refresh_token_model  # noqa: F401, E402


Base.metadata.create_all(bind=engine)

client = TestClient(app)


def test_signup_and_verify_and_login_flow():
    r = client.post(
        "/auth/signup",
        json={
            "username": "testuser",
            "email": "test@example.com",
            "password": "Secret123!",
            "display_name": "Test User",
        },
    )
    assert r.status_code == 200
    body = r.json()
    assert body["success"] is True
    assert body["data"]["username"] == "testuser"
    assert body["data"]["email"] == "test@example.com"
    assert body["data"]["email_verified"] is False
    assert body["data"]["is_active"] is False
    assert "hashed_password" not in body["data"]

    r2 = client.post(
        "/auth/signup",
        json={
            "username": "testuser",
            "email": "test@example.com",
            "password": "Secret123!",
            "display_name": "Test User",
        },
    )
    assert r2.status_code == 400
    assert r2.json()["error"] == "USERNAME_TAKEN"

    r3 = client.post(
        "/auth/signup",
        json={
            "username": "testuser2",
            "email": "test@example.com",
            "password": "Secret123!",
            "display_name": "Test User 2",
        },
    )
    assert r3.status_code == 400
    assert r3.json()["error"] == "EMAIL_TAKEN"


def test_unverified_account_cannot_login():
    client.post(
        "/auth/signup",
        json={
            "username": "unverified",
            "email": "unverified@example.com",
            "password": "Secret123!",
            "display_name": "Unverified",
        },
    )
    r = client.post("/auth/login", json={"username": "unverified", "password": "Secret123!"})
    assert r.status_code == 403
    assert r.json()["error"] == "UNVERIFIED_EMAIL"


def test_login_with_wrong_password():
    client.post(
        "/auth/signup",
        json={
            "username": "wrongpw",
            "email": "wrongpw@example.com",
            "password": "Secret123!",
            "display_name": "Wrong PW",
        },
    )
    from app.services.auth_service import hash_token
    from app.database import SessionLocal
    from app.models.player import Player

    db = SessionLocal()
    player = db.query(Player).filter(Player.username == "wrongpw").first()
    player.email_verified = True
    player.is_active = True
    db.commit()
    db.close()

    r = client.post("/auth/login", json={"username": "wrongpw", "password": "wrongpass"})
    assert r.status_code == 401
    assert r.json()["error"] == "INVALID_CREDENTIALS"


def test_login_returns_token_pair():
    client.post(
        "/auth/signup",
        json={
            "username": "tokenpair",
            "email": "tokenpair@example.com",
            "password": "Secret123!",
            "display_name": "Token Pair",
        },
    )
    from app.database import SessionLocal
    from app.models.player import Player

    db = SessionLocal()
    player = db.query(Player).filter(Player.username == "tokenpair").first()
    player.email_verified = True
    player.is_active = True
    db.commit()
    db.close()

    r = client.post("/auth/login", json={"username": "tokenpair", "password": "Secret123!"})
    assert r.status_code == 200
    body = r.json()
    assert body["success"] is True
    assert "access_token" in body["data"]
    assert "refresh_token" in body["data"]
    assert body["data"]["token_type"] == "bearer"


def test_me_requires_token():
    r = client.get("/auth/me")
    assert r.status_code == 401


def test_me_with_valid_token():
    client.post(
        "/auth/signup",
        json={
            "username": "metest",
            "email": "metest@example.com",
            "password": "Secret123!",
            "display_name": "Me Test",
        },
    )
    from app.database import SessionLocal
    from app.models.player import Player

    db = SessionLocal()
    player = db.query(Player).filter(Player.username == "metest").first()
    player.email_verified = True
    player.is_active = True
    db.commit()
    db.close()

    r = client.post("/auth/login", json={"username": "metest", "password": "Secret123!"})
    token = r.json()["data"]["access_token"]

    r2 = client.get("/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert r2.status_code == 200
    assert r2.json()["data"]["username"] == "metest"


def test_me_with_invalid_token():
    r = client.get("/auth/me", headers={"Authorization": "Bearer invalid-token"})
    assert r.status_code == 401


def test_password_validation():
    r = client.post(
        "/auth/signup",
        json={
            "username": "weakpw",
            "email": "weakpw@example.com",
            "password": "short",
            "display_name": "Weak PW",
        },
    )
    assert r.status_code == 422

    r2 = client.post(
        "/auth/signup",
        json={
            "username": "weakpw2",
            "email": "weakpw2@example.com",
            "password": "nouppercase1!",
            "display_name": "Weak PW 2",
        },
    )
    assert r2.status_code == 422

    r3 = client.post(
        "/auth/signup",
        json={
            "username": "weakpw3",
            "email": "weakpw3@example.com",
            "password": "NOLOWERCASE1!",
            "display_name": "Weak PW 3",
        },
    )
    assert r3.status_code == 422


def test_refresh_token_flow():
    client.post(
        "/auth/signup",
        json={
            "username": "refreshtest",
            "email": "refresh@example.com",
            "password": "Secret123!",
            "display_name": "Refresh Test",
        },
    )
    from app.database import SessionLocal
    from app.models.player import Player

    db = SessionLocal()
    player = db.query(Player).filter(Player.username == "refreshtest").first()
    player.email_verified = True
    player.is_active = True
    db.commit()
    db.close()

    r = client.post("/auth/login", json={"username": "refreshtest", "password": "Secret123!"})
    data = r.json()["data"]
    refresh_token = data["refresh_token"]
    old_access = data["access_token"]

    r2 = client.post("/auth/refresh", json={"refresh_token": refresh_token})
    assert r2.status_code == 200
    new_data = r2.json()["data"]
    assert new_data["access_token"] != old_access
    assert new_data["refresh_token"] != refresh_token

    r3 = client.post("/auth/refresh", json={"refresh_token": refresh_token})
    assert r3.status_code == 401
    assert r3.json()["error"] == "REVOKED_REFRESH_TOKEN"


def test_logout_revokes_refresh_token():
    client.post(
        "/auth/signup",
        json={
            "username": "logouttest",
            "email": "logout@example.com",
            "password": "Secret123!",
            "display_name": "Logout Test",
        },
    )
    from app.database import SessionLocal
    from app.models.player import Player

    db = SessionLocal()
    player = db.query(Player).filter(Player.username == "logouttest").first()
    player.email_verified = True
    player.is_active = True
    db.commit()
    db.close()

    r = client.post("/auth/login", json={"username": "logouttest", "password": "Secret123!"})
    refresh_token = r.json()["data"]["refresh_token"]

    r2 = client.post("/auth/logout", json={"refresh_token": refresh_token})
    assert r2.status_code == 200

    r3 = client.post("/auth/refresh", json={"refresh_token": refresh_token})
    assert r3.status_code == 401


def test_account_lockout():
    client.post(
        "/auth/signup",
        json={
            "username": "lockout",
            "email": "lockout@example.com",
            "password": "Secret123!",
            "display_name": "Lockout",
        },
    )
    from app.database import SessionLocal
    from app.models.player import Player

    db = SessionLocal()
    player = db.query(Player).filter(Player.username == "lockout").first()
    player.email_verified = True
    player.is_active = True
    db.commit()
    db.close()

    for _ in range(5):
        client.post("/auth/login", json={"username": "lockout", "password": "wrongpassword"})

    r = client.post("/auth/login", json={"username": "lockout", "password": "Secret123!"})
    assert r.status_code == 423
    assert r.json()["error"] == "ACCOUNT_LOCKED"


def test_disposable_email_rejected():
    r = client.post(
        "/auth/signup",
        json={
            "username": "disposable",
            "email": "user@mailinator.com",
            "password": "Secret123!",
            "display_name": "Disposable",
        },
    )
    assert r.status_code == 422


def test_email_verification():
    client.post(
        "/auth/signup",
        json={
            "username": "verifytest",
            "email": "verify@example.com",
            "password": "Secret123!",
            "display_name": "Verify Test",
        },
    )
    from app.database import SessionLocal
    from app.models.player import Player
    from app.services.auth_service import hash_token

    db = SessionLocal()
    player = db.query(Player).filter(Player.username == "verifytest").first()
    raw_token = "test-verification-token"
    player.email_verification_token = hash_token(raw_token)
    db.commit()
    db.close()

    r = client.get(f"/auth/verify-email?token={raw_token}")
    assert r.status_code == 200
    assert r.json()["success"] is True
    assert r.json()["data"]["email_verified"] is True
    assert r.json()["data"]["is_active"] is True


def test_password_change():
    client.post(
        "/auth/signup",
        json={
            "username": "changepw",
            "email": "changepw@example.com",
            "password": "OldPass123!",
            "display_name": "Change PW",
        },
    )
    from app.database import SessionLocal
    from app.models.player import Player

    db = SessionLocal()
    player = db.query(Player).filter(Player.username == "changepw").first()
    player.email_verified = True
    player.is_active = True
    db.commit()
    db.close()

    r = client.post("/auth/login", json={"username": "changepw", "password": "OldPass123!"})
    token = r.json()["data"]["access_token"]

    r2 = client.put(
        "/auth/change-password",
        headers={"Authorization": f"Bearer {token}"},
        json={"current_password": "OldPass123!", "new_password": "NewPass456!"},
    )
    assert r2.status_code == 200

    r3 = client.post("/auth/login", json={"username": "changepw", "password": "OldPass123!"})
    assert r3.status_code == 401

    r4 = client.post("/auth/login", json={"username": "changepw", "password": "NewPass456!"})
    assert r4.status_code == 200
