from datetime import timedelta
from pathlib import Path
from types import SimpleNamespace

import pytest

from app.core.clock import utcnow
from app.core.config import settings
from app.modules.auth import email, oauth
from app.modules.farming.schemas import PlantRequest, RelocateRequest, TileRequest
from app.modules.farming.service import FarmingService, SCENE_DURATIONS
from app.modules.inventory.schemas import ItemRequest
from app.modules.inventory.service import InventoryService
from app.modules.profile.models import PlayerProfile


def test_google_browser_code_exchange_validates_nonce_and_keeps_secret_server_side(client, monkeypatch):
    monkeypatch.setattr(settings, "google_client_id", "desktop-client")
    monkeypatch.setattr(settings, "google_client_secret", "server-only-secret")
    captured = {}

    def exchange(url, data, timeout):
        captured.update(data)
        assert url == "https://oauth2.googleapis.com/token" and timeout == 10
        return SimpleNamespace(raise_for_status=lambda: None, json=lambda: {"id_token": "signed-token"})

    monkeypatch.setattr(oauth.requests, "post", exchange)
    monkeypatch.setattr(oauth.id_token, "verify_oauth2_token", lambda *_: {
        "sub": "browser-user", "email": "browser@gmail.com", "email_verified": True,
        "nonce": "n" * 64,
    })
    payload = {"code": "one-use-code", "code_verifier": "v" * 64,
               "redirect_uri": "http://127.0.0.1:53123/oauth/callback", "nonce": "n" * 64}
    response = client.post("/auth/google/code", json=payload)
    assert response.status_code == 200, response.text
    assert response.json()["data"]["player"]["email_verified"]
    assert captured["client_secret"] == "server-only-secret"
    assert captured["code_verifier"] == payload["code_verifier"]
    config = client.get("/auth/config")
    assert config.json()["data"]["google_client_id"] == "desktop-client"
    assert "secret" not in config.text
    assert "server-only-secret" not in response.text
    payload["nonce"] = "wrong" * 10
    assert client.post("/auth/google/code", json=payload).status_code == 401


@pytest.mark.parametrize("redirect", ["https://attacker.example/oauth/callback", "http://127.0.0.1.attacker.example:123/oauth/callback", "http://user@127.0.0.1:123/oauth/callback"])
def test_google_exchange_rejects_non_loopback_callbacks(client, redirect):
    response = client.post("/auth/google/code", json={"code": "code", "code_verifier": "v" * 64,
                           "redirect_uri": redirect, "nonce": "n" * 64})
    assert response.status_code == 422


def test_email_browser_pages_and_explicit_smtp(client, account, monkeypatch):
    user = account(verify=False)
    response = client.get("/auth/verify-email", params={"token": user.verify_token}, headers={"Accept": "text/html"})
    assert "text/html" in response.headers["content-type"]
    assert "Email verified" in response.text and user.verify_token not in response.text
    assert client.get("/auth/reset-password").status_code == 200
    monkeypatch.setattr(settings, "email_delivery", "smtp")
    monkeypatch.setattr(settings, "smtp_user", "sender@example.com")
    monkeypatch.setattr(settings, "smtp_password", "private-password")
    sent = []

    class SMTP:
        def __init__(self, *args, **kwargs): pass
        def __enter__(self): return self
        def __exit__(self, *args): pass
        def starttls(self, **kwargs): sent.append("tls")
        def login(self, user, password): sent.append("login")
        def send_message(self, message): sent.append(message)

    monkeypatch.setattr(email.smtplib, "SMTP", SMTP)
    # The suite replaces send_account_email; exercise the original function here.
    import importlib
    original = importlib.reload(email).send_account_email
    monkeypatch.setattr(email, "send_account_email", original)
    original("reader@example.com", "Reader", "private-token", "password_reset")
    assert sent[:2] == ["tls", "login"]
    assert "/auth/reset-password?token=private-token" in sent[-1].get_content()
    assert client.get("/auth/config").json()["data"]["email_delivery"] == "smtp"


def test_readiness_checks_seed_and_schema(client, db):
    assert client.get("/ready").json()["data"]["database"] == "connected"
    from app.modules.shop.models import ItemRule
    db.delete(db.get(ItemRule, "wheat_seed"))
    db.commit()
    assert client.get("/ready").status_code == 503


def test_brevo_delivery_uses_https_and_reports_failure(client, monkeypatch):
    import importlib
    import requests
    from app.core.config import settings

    original = importlib.reload(email).send_account_email
    monkeypatch.setattr(email, "send_account_email", original)
    monkeypatch.setattr(settings, "email_delivery", "brevo")
    monkeypatch.setattr(settings, "brevo_api_key", "test-key")
    captured = []

    class Response:
        def raise_for_status(self):
            pass

    def post(url, **kwargs):
        captured.append((url, kwargs))
        return Response()

    monkeypatch.setattr(email.requests, "post", post)
    assert email.deliver_safely("reader@example.com", "Reader", "private-token", "email_verification")
    url, kwargs = captured[0]
    assert url == "https://api.brevo.com/v3/smtp/email"
    assert kwargs["headers"]["api-key"] == "test-key"
    assert "/auth/verify-email?token=private-token" in kwargs["json"]["textContent"]
    assert kwargs["timeout"] == 10
    assert client.get("/auth/config").json()["data"]["email_delivery"] == "brevo"

    def unavailable(*args, **kwargs):
        raise requests.Timeout()

    monkeypatch.setattr(email.requests, "post", unavailable)
    assert not email.deliver_safely("reader@example.com", "Reader", "private-token", "email_verification")


def test_inventory_exposes_actual_partition_capacity(client, account, db):
    from app.core.config import settings

    user = account("hud_inventory")
    InventoryService(db).add_compatibility(user.id, ItemRequest(item_code="wheat_seed", quantity=3))
    InventoryService(db).add_compatibility(user.id, ItemRequest(item_code="wheat", quantity=2))
    data = client.get("/inventory/", headers=user.headers).json()["data"]
    assert data["partition_capacity"] == settings.inventory_partition_slots
    assert data["partitions"]["seeds"] == 1
    assert data["partitions"]["crops"] == 1
    assert {r["item_code"]: r["partition"] for r in data["items"]} == {"wheat_seed": "seeds", "wheat": "crops"}


def test_signup_delivery_failure_keeps_account_and_explains_resend(client, monkeypatch):
    def fail(*_):
        raise OSError("mail unavailable")

    monkeypatch.setattr(email, "send_account_email", fail)
    payload = {"username": "mail_failure", "email": "mailfailure@example.com", "password": "Strong-Pass123!"}
    result = client.post("/auth/signup", json=payload)
    assert result.status_code == 503
    assert result.json()["error"] == "EMAIL_DELIVERY_FAILED"
    assert "account was created" in result.json()["message"]
    assert client.post("/auth/signup", json=payload).json()["error"] == "USERNAME_TAKEN"
    assert client.post("/auth/resend-verification", json={"email": payload["email"]}).status_code == 200


@pytest.mark.parametrize("code,total,last_frame", [("wheat", 18, 4), ("potato", 22, 5)])
def test_inspector_crop_timing_and_relocation_preserve_growth(client, account, db, code, total, last_frame):
    user, other = account(), account("other_farmer")
    from app.modules.world.models import WorldState
    db.get(WorldState, 1).current_season = "winter" if code == "potato" else "summer"
    db.commit()
    InventoryService(db).add_compatibility(user.id, ItemRequest(item_code=code + "_seed"))
    farm = FarmingService(db)
    now = utcnow()
    source = farm.plant(user.id, PlantRequest(x=1, y=1, item_code=code + "_seed"), now).plot
    assert farm.list(user.id, now + timedelta(days=1)).plots[0].visual_frame == 0
    assert farm.water(user.id, source.id, now).visual_frame == 1
    assert farm.list(user.id, now + timedelta(seconds=5)).plots[0].visual_frame == 2
    farm.till(user.id, TileRequest(x=2, y=1), now)
    relocated = farm.relocate(user.id, RelocateRequest(plot_id=source.id, x=2, y=1), now + timedelta(seconds=11))
    assert relocated["source"].item_code is None
    assert relocated["plot"].visual_frame == 3
    assert db.get(PlayerProfile, user.id).water_charges == 19
    plots = farm.list(user.id, now + timedelta(seconds=total)).plots
    assert plots[1].ready and plots[1].visual_frame == last_frame
    assert client.post("/farm/relocate", headers=other.headers, json={"plot_id": plots[1].id, "x": 1, "y": 1}).status_code == 404
    assert client.post("/farm/relocate", headers=user.headers, json={"plot_id": plots[1].id, "x": 16, "y": 20}).status_code == 409
    farm.harvest(user.id, plots[1].id, now + timedelta(seconds=total))
    assert db.get(PlayerProfile, user.id).water_charges == 19


def test_crop_scene_frame_counts_match_server():
    client_root = Path(__file__).resolve().parents[3] / "client"
    for code, durations in SCENE_DURATIONS.items():
        scene = (client_root / f"Scenes/crops/{code}.tscn").read_text()
        assert scene.count('"texture":') == len(durations) + 2
        assert "frame_durations =" not in scene  # Inspector uses CropVisual defaults.
    assert "[5.0, 6.0, 7.0, 4.0]" in (client_root / "Scripts/crop_visual.gd").read_text()


def test_disconnect_updates_friend_presence_and_reconnect_restores_position(client, account):
    user, other = account(), account("socket_friend")
    client.post("/social/requests", headers=user.headers, json={"target_id": other.id})
    client.post(f"/social/friends/{user.id}", headers=other.headers, json={"action": "accept"})
    with client.websocket_connect("/realtime/ws") as socket:
        socket.send_json({"type": "auth", "token": user.tokens["access_token"]})
        snapshot = socket.receive_json()["data"]
        own = next(p for p in snapshot["players"] if p["player_id"] == user.id)
        assert client.get("/social/friends", headers=other.headers).json()["data"][0]["online"]
    assert not client.get("/social/friends", headers=other.headers).json()["data"][0]["online"]
    with client.websocket_connect("/realtime/ws") as socket:
        socket.send_json({"type": "auth", "token": user.tokens["access_token"]})
        restored = socket.receive_json()["data"]["players"][0]
        assert (restored["x"], restored["y"], restored["sequence"]) == (own["x"], own["y"], own["sequence"])
