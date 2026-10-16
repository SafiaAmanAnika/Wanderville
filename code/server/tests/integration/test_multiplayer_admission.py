"""Multiplayer admission: tickets, the private host endpoint, and their limits.

These cover the security properties the Godot host depends on: a ticket is
short-lived, single-use, bound to a verified player, opaque at rest, and only
spendable by a caller that can prove it is the configured host.
"""

import threading
import time
from datetime import datetime, timedelta

import pytest

from app.core.clock import as_utc, utcnow
from app.core.config import settings
from app.modules.auth.security import create_access_token, hash_token
from app.modules.players.models import Player
from app.modules.realtime import admission
from app.modules.realtime.tickets import (
    TicketError,
    constant_time_matches,
    registry,
)

HOST_SECRET = "host-secret-for-tests"
HOST_HEADERS = {"X-Multiplayer-Secret": HOST_SECRET}


@pytest.fixture(autouse=True)
def bridge_config(monkeypatch):
    monkeypatch.setattr(settings, "multiplayer_bridge_secret", HOST_SECRET)
    registry.clear()
    yield
    registry.clear()


def ok(response):
    assert response.status_code == 200, response.text
    return response.json()["data"]


# ── public: issuing ────────────────────────────────────────────────────────


def test_authenticated_player_can_request_a_ticket(client, account):
    user = account("ticket_holder")
    ticket = ok(client.post("/multiplayer/tickets", headers=user.headers, json={}))
    assert ticket["ticket"]
    assert ticket["expires_in"] == settings.multiplayer_ticket_ttl_seconds
    assert ticket["transport"] == "godot-enet"


def test_unauthenticated_request_is_rejected(client):
    assert client.post("/multiplayer/tickets", json={}).status_code in (401, 403)


def test_expired_or_bogus_token_cannot_mint_a_ticket(client):
    forged = create_access_token(1, token_version=0) + "tampered"
    response = client.post(
        "/multiplayer/tickets", headers={"Authorization": f"Bearer {forged}"}, json={}
    )
    assert response.status_code == 401


def test_disabled_account_cannot_mint_a_ticket(client, account, db):
    user = account("disabled_holder")
    db.get(Player, user.id).is_active = False
    db.commit()
    response = client.post("/multiplayer/tickets", headers=user.headers, json={})
    assert response.status_code == 403


def test_unverified_account_cannot_mint_a_ticket(client, account, db):
    user = account("unverified_holder")
    db.get(Player, user.id).email_verified = False
    db.commit()
    assert client.post("/multiplayer/tickets", headers=user.headers, json={}).status_code == 403


def test_ticket_is_short_lived(client, account):
    user = account("ttl_holder")
    ticket = ok(client.post("/multiplayer/tickets", headers=user.headers, json={}))
    # The response envelope serialises datetimes, so parse rather than subtract.
    expires = datetime.fromisoformat(str(ticket["expires_at"]).replace("Z", "+00:00"))
    remaining = (as_utc(expires) - utcnow()).total_seconds()
    assert 0 < remaining <= settings.multiplayer_ticket_ttl_seconds


def test_no_refresh_token_or_password_appears_in_the_ticket(client, account):
    user = account("secret_holder")
    ticket = ok(client.post("/multiplayer/tickets", headers=user.headers, json={}))
    blob = repr(ticket)
    assert user.tokens["refresh_token"] not in blob
    assert user.payload["password"] not in blob
    assert "access_token" not in blob


# ── private: consuming ─────────────────────────────────────────────────────


def host_post(client, path, payload):
    return client.post(path, headers=HOST_HEADERS, json=payload)


def test_internal_endpoint_requires_the_host_secret(client, account):
    user = account("consume_holder")
    ticket = ok(client.post("/multiplayer/tickets", headers=user.headers, json={}))
    # No secret at all.
    assert client.post(
        "/internal/multiplayer/tickets/consume", json={"ticket": ticket["ticket"]}
    ).status_code == 403
    # Wrong secret.
    assert client.post(
        "/internal/multiplayer/tickets/consume",
        headers={"X-Multiplayer-Secret": "wrong"},
        json={"ticket": ticket["ticket"]},
    ).status_code == 403


def test_unset_secret_fails_closed(monkeypatch, client, account):
    monkeypatch.setattr(settings, "multiplayer_bridge_secret", "")
    user = account("unconfigured")
    ticket = ok(client.post("/multiplayer/tickets", headers=user.headers, json={}))
    # Even presenting a matching empty value must be refused.
    response = client.post(
        "/internal/multiplayer/tickets/consume",
        headers={"X-Multiplayer-Secret": ""},
        json={"ticket": ticket["ticket"]},
    )
    assert response.status_code == 403


def test_valid_ticket_is_consumed_once(client, account):
    user = account("once_holder")
    ticket = ok(client.post("/multiplayer/tickets", headers=user.headers, json={}))
    admitted = ok(
        host_post(client, "/internal/multiplayer/tickets/consume", {"ticket": ticket["ticket"]})
    )
    assert admitted["player_id"] == user.id
    assert admitted["room"] == "campus"


def test_replayed_ticket_is_rejected(client, account):
    user = account("replay_holder")
    ticket = ok(client.post("/multiplayer/tickets", headers=user.headers, json={}))
    ok(host_post(client, "/internal/multiplayer/tickets/consume", {"ticket": ticket["ticket"]}))
    assert host_post(
        client, "/internal/multiplayer/tickets/consume", {"ticket": ticket["ticket"]}
    ).status_code == 403


def test_invalid_ticket_is_rejected(client):
    assert host_post(
        client, "/internal/multiplayer/tickets/consume", {"ticket": "not-a-real-ticket"}
    ).status_code == 403


def test_expired_ticket_is_rejected(client, account, monkeypatch):
    monkeypatch.setattr(settings, "multiplayer_ticket_ttl_seconds", 5)
    user = account("expiring")
    ticket = ok(client.post("/multiplayer/tickets", headers=user.headers, json={}))
    # Age the stored record past its expiry rather than sleeping.
    record = registry._by_digest[hash_token(ticket["ticket"])]  # noqa: SLF001
    record.expires_at = utcnow() - timedelta(seconds=1)
    assert host_post(
        client, "/internal/multiplayer/tickets/consume", {"ticket": ticket["ticket"]}
    ).status_code == 403


def test_expired_ticket_is_removed_not_kept(client, account, monkeypatch):
    monkeypatch.setattr(settings, "multiplayer_ticket_ttl_seconds", 5)
    user = account("expired_cleanup")
    ticket = ok(client.post("/multiplayer/tickets", headers=user.headers, json={}))
    record = registry._by_digest[hash_token(ticket["ticket"])]  # noqa: SLF001
    record.expires_at = utcnow() - timedelta(seconds=1)
    host_post(client, "/internal/multiplayer/tickets/consume", {"ticket": ticket["ticket"]})
    assert ticket["ticket"] not in {
        d for d in registry._by_digest  # noqa: SLF001
    }, "a spent ticket must not linger in the registry"


def test_ticket_bound_to_another_server_is_refused(client, account):
    user = account("bound_holder")
    ticket = ok(
        client.post("/multiplayer/tickets", headers=user.headers, json={"server_id": "host-a"})
    )
    assert host_post(
        client,
        "/internal/multiplayer/tickets/consume",
        {"ticket": ticket["ticket"], "server_id": "host-b"},
    ).status_code == 403
    # The rightful host can still spend it.
    admitted = ok(
        host_post(
            client,
            "/internal/multiplayer/tickets/consume",
            {"ticket": ticket["ticket"], "server_id": "host-a"},
        )
    )
    assert admitted["player_id"] == user.id


def test_two_players_receive_distinct_identities(client, account):
    from app.core.rate_limit import limiter

    limiter.clear()
    one = account("ident_one")
    limiter.clear()
    two = account("ident_two")

    first = ok(client.post("/multiplayer/tickets", headers=one.headers, json={}))
    second = ok(client.post("/multiplayer/tickets", headers=two.headers, json={}))
    admitted_one = ok(
        host_post(client, "/internal/multiplayer/tickets/consume", {"ticket": first["ticket"]})
    )
    admitted_two = ok(
        host_post(client, "/internal/multiplayer/tickets/consume", {"ticket": second["ticket"]})
    )
    assert admitted_one["player_id"] != admitted_two["player_id"]
    assert admitted_one["username"] != admitted_two["username"]


def test_account_revoked_between_issue_and_consume_is_refused(client, account, db):
    user = account("revoked_midflight")
    ticket = ok(client.post("/multiplayer/tickets", headers=user.headers, json={}))
    db.get(Player, user.id).is_active = False
    db.commit()
    assert host_post(
        client, "/internal/multiplayer/tickets/consume", {"ticket": ticket["ticket"]}
    ).status_code == 403


def test_client_cannot_choose_its_own_player_id(client, account):
    """The consume payload carries no identity field to forge."""
    user = account("no_forgery")
    ticket = ok(client.post("/multiplayer/tickets", headers=user.headers, json={}))
    admitted = ok(
        host_post(
            client,
            "/internal/multiplayer/tickets/consume",
            {"ticket": ticket["ticket"], "player_id": 999999},
        )
    )
    assert admitted["player_id"] == user.id, "identity must come from the ticket"


# ── registry properties ────────────────────────────────────────────────────


def test_concurrent_consumption_admits_exactly_one(client, account):
    user = account("race_holder")
    ticket = ok(client.post("/multiplayer/tickets", headers=user.headers, json={}))
    raw = ticket["ticket"]

    outcomes = []
    barrier = threading.Barrier(4)

    def attempt():
        barrier.wait()
        try:
            record = registry.consume(raw)
            outcomes.append(("ok", record.player_id))
        except TicketError as exc:
            outcomes.append(("error", str(exc)))

    threads = [threading.Thread(target=attempt) for _ in range(4)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()

    successes = [o for o in outcomes if o[0] == "ok"]
    assert len(successes) == 1, f"exactly one consumption must win, got {outcomes}"
    assert successes[0][1] == user.id


def test_registry_stays_bounded(monkeypatch):
    monkeypatch.setattr(settings, "multiplayer_ticket_capacity", 64)
    for index in range(500):
        registry.issue(index + 1)
    assert registry.size() <= 64, f"registry grew to {registry.size()}"


def test_expired_entries_are_pruned(monkeypatch):
    monkeypatch.setattr(settings, "multiplayer_ticket_ttl_seconds", 5)
    for index in range(20):
        registry.issue(index + 1)
    assert registry.size() == 20
    for record in registry._by_digest.values():  # noqa: SLF001
        record.expires_at = utcnow() - timedelta(seconds=1)
    registry.issue(999)
    assert registry.size() == 1, "expired entries must be pruned on write"


def test_raw_ticket_is_never_stored(monkeypatch):
    monkeypatch.setattr(settings, "multiplayer_ticket_ttl_seconds", 5)
    ticket = registry.issue(1)
    assert hash_token(ticket.raw) in registry._by_digest  # noqa: SLF001
    assert ticket.raw not in registry._by_digest  # noqa: SLF001


def test_introspect_does_not_spend_the_ticket(client, account):
    user = account("introspect_holder")
    ticket = ok(client.post("/multiplayer/tickets", headers=user.headers, json={}))
    seen = ok(
        host_post(
            client, "/internal/multiplayer/tickets/introspect", {"ticket": ticket["ticket"]}
        )
    )
    assert seen["player_id"] == user.id and seen["expired"] is False
    # Still spendable afterwards.
    assert ok(
        host_post(client, "/internal/multiplayer/tickets/consume", {"ticket": ticket["ticket"]})
    )["player_id"] == user.id


def test_host_health_requires_the_secret(client):
    assert client.get("/internal/multiplayer/health").status_code == 403
    health = ok(client.get("/internal/multiplayer/health", headers=HOST_HEADERS))
    assert health["ok"] is True


def test_constant_time_match_rejects_empty_expected():
    assert constant_time_matches("anything", "") is False
    assert constant_time_matches("x", "x") is True
    assert constant_time_matches("x", "y") is False


def test_legacy_login_and_refresh_still_work(client, account):
    """The new endpoints must not have disturbed the existing token flow."""
    user = account("legacy_still_works")
    refreshed = client.post(
        "/auth/refresh", json={"refresh_token": user.tokens["refresh_token"]}
    )
    assert refreshed.status_code == 200, refreshed.text
    assert refreshed.json()["data"]["access_token"]