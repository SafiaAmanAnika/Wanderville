from datetime import timedelta

import pytest
from jose import jwt
from sqlalchemy import select

from app.core.clock import utcnow
from app.core.config import settings
from app.modules.auth import oauth, security
from app.modules.auth.models import AccountToken, RefreshToken
from app.modules.auth.schemas import SignupRequest
from app.modules.auth.service import AuthService
from app.modules.players.models import Player
from app.modules.world.models import PlayerWorld
from app.modules.world.repository import WorldRepository


def test_signup_atomic_failure(db, monkeypatch):
    def fail(*args):
        raise RuntimeError("injected world failure")

    monkeypatch.setattr(WorldRepository, "create", fail)
    with pytest.raises(RuntimeError):
        AuthService(db).signup(
            SignupRequest(
                username="rollback",
                email="rollback@example.com",
                password="Strong-Pass123!",
            )
        )
    assert db.scalar(select(Player)) is None
    assert db.scalar(select(AccountToken)) is None


def test_duplicate_username_email_and_weak_password(client, account):
    user = account()
    result = client.post(
        "/auth/signup", json={**user.payload, "email": "different@example.com"}
    )
    assert result.json()["error"] == "USERNAME_TAKEN"
    result = client.post("/auth/signup", json={**user.payload, "username": "different"})
    assert result.json()["error"] == "EMAIL_TAKEN"
    result = client.post(
        "/auth/signup",
        json={**user.payload, "username": "newplayer", "password": "weak"},
    )
    assert result.status_code == 422


def test_unverified_inactive_lockout_and_recovery(client, account, db):
    unverified = account(verify=False)
    request = {"username": "player_one", "password": unverified.payload["password"]}
    assert (
        client.post("/auth/login", json=request).json()["error"] == "EMAIL_NOT_VERIFIED"
    )
    client.get("/auth/verify-email", params={"token": unverified.verify_token})
    for _ in range(settings.max_login_attempts):
        assert (
            client.post(
                "/auth/login", json={**request, "password": "wrong"}
            ).status_code
            == 401
        )
    assert client.post("/auth/login", json=request).json()["error"] == "ACCOUNT_internal"
    player = db.get(Player, unverified.id)
    player.locked_until = utcnow() - timedelta(seconds=1)
    db.commit()
    assert client.post("/auth/login", json=request).status_code == 200
    db.refresh(player)
    assert player.failed_login_attempts == 0
    player.is_active = False
    db.commit()
    assert (
        client.post("/auth/login", json=request).json()["error"] == "INACTIVE_ACCOUNT"
    )


def test_tokens_hashed_rotated_revoked_and_expired(client, account, db):
    user = account()
    raw = user.tokens["refresh_token"]
    row = db.scalar(select(RefreshToken))
    assert row.token_hash == security.hash_token(raw) and row.token_hash != raw
    rotated = client.post("/auth/refresh", json={"refresh_token": raw})
    assert rotated.status_code == 200
    fresh = rotated.json()["data"]["refresh_token"]
    assert fresh != raw
    assert client.post("/auth/refresh", json={"refresh_token": raw}).status_code == 401
    assert client.post("/auth/logout", json={"refresh_token": fresh}).status_code == 200
    assert (
        client.post("/auth/refresh", json={"refresh_token": fresh}).status_code == 401
    )
    db.rollback()
    row = db.scalar(
        select(RefreshToken).where(RefreshToken.token_hash == security.hash_token(raw))
    )
    row.revoked_at, row.expires_at = None, utcnow() - timedelta(days=1)
    db.commit()
    assert (
        client.post("/auth/refresh", json={"refresh_token": raw}).json()["error"]
        == "EXPIRED_REFRESH_TOKEN"
    )


def test_access_tokens_invalid_expired_and_inactive(client, account, db):
    user = account()
    for token in [
        "invalid",
        jwt.encode(
            {
                "sub": str(user.id),
                "type": "access",
                "ver": 0,
                "jti": "x",
                "iat": 0,
                "exp": 1,
            },
            settings.jwt_secret_key,
            algorithm="HS256",
        ),
        jwt.encode(
            {"sub": str(user.id), "type": "access"},
            settings.jwt_secret_key,
            algorithm="HS256",
        ),
    ]:
        assert (
            client.get(
                "/auth/me", headers={"Authorization": f"Bearer {token}"}
            ).status_code
            == 401
        )
    player = db.get(Player, user.id)
    player.is_active = False
    db.commit()
    assert client.get("/auth/me", headers=user.headers).status_code == 403


def test_reset_is_private_single_use_and_revokes_sessions(client, account, mailbox, db):
    user = account()
    existing = client.post(
        "/auth/forgot-password", json={"email": user.payload["email"]}
    )
    raw = mailbox[-1][2]
    missing = client.post(
        "/auth/forgot-password", json={"email": "missing@example.com"}
    )
    assert existing.json() == missing.json()
    row = db.scalar(
        select(AccountToken).where(AccountToken.token_type == "password_reset")
    )
    assert row.token_hash == security.hash_token(raw)
    request = {"token": raw, "new_password": "Different-Pass123!"}
    assert client.post("/auth/reset-password", json=request).status_code == 200
    assert client.post("/auth/reset-password", json=request).status_code == 400
    assert client.get("/auth/me", headers=user.headers).status_code == 401
    assert (
        client.post(
            "/auth/refresh", json={"refresh_token": user.tokens["refresh_token"]}
        ).status_code
        == 401
    )
    assert (
        client.post(
            "/auth/login",
            json={
                "username": user.payload["username"],
                "password": request["new_password"],
            },
        ).status_code
        == 200
    )


def test_verification_resend_invalidates_previous_token(client, account, mailbox, db):
    user = account(verify=False)
    client.post("/auth/resend-verification", json={"email": user.payload["email"]})
    raw = mailbox[-1][2]
    assert raw != user.verify_token
    assert (
        client.get(
            "/auth/verify-email", params={"token": user.verify_token}
        ).status_code
        == 400
    )
    row = db.scalar(
        select(AccountToken).where(AccountToken.token_hash == security.hash_token(raw))
    )
    row.expires_at = utcnow() - timedelta(seconds=1)
    db.commit()
    assert (
        client.get("/auth/verify-email", params={"token": raw}).json()["error"]
        == "TOKEN_EXPIRED"
    )


def test_spent_verification_link_reports_already_verified(client, account, mailbox):
    # The frozen client renders a dedicated "already verified" screen for this code.
    user = account()
    raw = mailbox[-1][2]
    response = client.get("/auth/verify-email", params={"token": raw})
    assert response.status_code == 400
    assert response.json()["error"] == "ALREADY_VERIFIED"
    assert client.get("/auth/me", headers=user.headers).status_code == 200


def test_spent_reset_link_reports_invalid_token(client, account, mailbox):
    user = account()
    client.post("/auth/forgot-password", json={"email": user.payload["email"]})
    raw = mailbox[-1][2]
    body = {"token": raw, "new_password": "Another-Pass123!"}
    assert client.post("/auth/reset-password", json=body).status_code == 200
    response = client.post("/auth/reset-password", json=body)
    assert response.status_code == 400
    assert response.json()["error"] == "INVALID_TOKEN"


def test_expired_reset_link_preserves_credentials_and_session(
    client, account, mailbox, db
):
    user = account()
    client.post("/auth/forgot-password", json={"email": user.payload["email"]})
    raw = mailbox[-1][2]
    row = db.scalar(
        select(AccountToken).where(AccountToken.token_hash == security.hash_token(raw))
    )
    row.expires_at = utcnow() - timedelta(seconds=1)
    db.commit()
    response = client.post(
        "/auth/reset-password",
        json={"token": raw, "new_password": "Another-Pass123!"},
    )
    assert response.status_code == 400
    assert response.json()["error"] == "TOKEN_EXPIRED"
    db.refresh(row)
    assert row.used_at is None
    assert client.get("/auth/me", headers=user.headers).status_code == 200
    assert (
        client.post(
            "/auth/login",
            json={
                "username": user.payload["username"],
                "password": user.payload["password"],
            },
        ).status_code
        == 200
    )


def test_change_password_revokes_access_and_refresh(client, account):
    user = account()
    req = {
        "current_password": user.payload["password"],
        "new_password": "Changed-Pass123!",
    }
    assert (
        client.put("/auth/change-password", headers=user.headers, json=req).status_code
        == 200
    )
    assert client.get("/auth/me", headers=user.headers).status_code == 401
    assert (
        client.post(
            "/auth/refresh", json={"refresh_token": user.tokens["refresh_token"]}
        ).status_code
        == 401
    )


def test_google_signup_is_atomic_and_inactive_stays_inactive(client, db, monkeypatch):
    monkeypatch.setattr(
        oauth,
        "verify_google",
        lambda _: oauth.GoogleIdentity(
            "subject", "google@example.com", "Google Player", None, True
        ),
    )
    result = client.post("/auth/google", json={"id_token": "test"})
    assert result.status_code == 200, result.text
    pid = result.json()["data"]["player"]["id"]
    assert db.scalar(select(PlayerWorld).where(PlayerWorld.owner_id == pid))
    player = db.get(Player, pid)
    player.is_active = False
    db.commit()
    assert client.post("/auth/google", json={"id_token": "test"}).status_code == 403


def test_google_must_be_configured_and_untrusted_email_cannot_link(
    client, account, monkeypatch
):
    user = account()
    monkeypatch.setattr(settings, "google_client_id", "")
    assert client.post("/auth/google", json={"id_token": "test"}).status_code == 503
    monkeypatch.setattr(
        oauth,
        "verify_google",
        lambda _: oauth.GoogleIdentity(
            "other", user.payload["email"], "Google", None, False
        ),
    )
    assert (
        client.post("/auth/google", json={"id_token": "test"}).json()["error"]
        == "ACCOUNT_LINK_REQUIRED"
    )


def test_rate_limit_sensitive_endpoint(client):
    for _ in range(3):
        assert (
            client.post(
                "/auth/forgot-password", json={"email": "missing@example.com"}
            ).status_code
            == 200
        )
    assert (
        client.post(
            "/auth/forgot-password", json={"email": "missing@example.com"}
        ).status_code
        == 429
    )
