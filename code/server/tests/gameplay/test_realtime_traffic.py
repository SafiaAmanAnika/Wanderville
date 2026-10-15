"""Traffic reduction must preserve authorization, delivery and time boundaries."""

from contextlib import contextmanager
from datetime import timedelta

import pytest
from sqlalchemy import event, update

from app.core.clock import utcnow
from app.core.config import settings
from app.modules.players.models import Player
from app.modules.realtime.models import NearbyMessage, Presence
from app.modules.realtime.protocol import RealtimeProtocol
from app.modules.realtime.runtime import runtime
from app.modules.realtime import snapshot_cache
from app.modules.social.models import PlayerBlock


@contextmanager
def queries(db):
    statements = []

    def record(_conn, _cursor, statement, _parameters, _context, _many):
        statements.append(statement)

    engine = db.get_bind()
    event.listen(engine, "before_cursor_execute", record)
    try:
        yield statements
    finally:
        event.remove(engine, "before_cursor_execute", record)


@pytest.fixture
def socket_player(client, account, db, monkeypatch):
    now = [100.0]
    monkeypatch.setattr(snapshot_cache, "monotonic", lambda: now[0])
    monkeypatch.setattr(settings, "realtime_snapshot_cache_seconds", 1.0)
    user = account("traffic_player")
    generation = runtime.attach(user.id)
    protocol = RealtimeProtocol(db)
    token = user.tokens["access_token"]

    def step(kind="snapshot", **extra):
        return protocol.step(token, {"type": kind, **extra}, 2, generation)

    assert step("enter")["type"] == "snapshot"
    assert step()["type"] == "snapshot"
    yield user, protocol, step, now
    runtime.detach(user.id, generation)


def test_idle_frames_do_no_sql_and_do_not_renew_voice_policy(socket_player, db):
    user, protocol, step, now = socket_player
    policy_until = runtime.connections[user.id].policy_until
    with queries(db) as statements:
        for _ in range(10):
            assert step("heartbeat")["type"] == "snapshot"
            assert step()["type"] == "snapshot"
    assert statements == []
    assert runtime.connections[user.id].policy_until == policy_until
    now[0] += 1.01
    with queries(db) as refreshed:
        assert step()["type"] == "snapshot"
    assert refreshed  # Bounded refresh also detects out-of-process changes.


def test_projection_reuse_cannot_be_poisoned_by_packet_mutation(socket_player):
    _, _, step, _ = socket_player
    packet = step()
    packet["data"]["players"].clear()
    packet["events"].append({"type": "untrusted"})
    next_packet = step()
    assert next_packet["data"]["players"]
    assert next_packet["events"] == []


@pytest.mark.parametrize("field,value", [
    ("is_active", False), ("email_verified", False), ("token_version", 1),
])
def test_account_revocation_immediately_invalidates_cached_auth(socket_player, db, field, value):
    user, _, step, _ = socket_player
    setattr(db.get(Player, user.id), field, value)
    db.commit()
    assert step()["type"] == "error"


def test_jwt_expiry_is_checked_even_on_cached_frames(socket_player, monkeypatch):
    from app.core.exceptions import InvalidToken

    _, _, step, _ = socket_player

    def expired(_token):
        raise InvalidToken()

    monkeypatch.setattr(snapshot_cache, "decode_access_token", expired)
    assert step()["status"] == 401


def test_bulk_account_update_invalidates_projection(socket_player, db):
    user, _, step, _ = socket_player
    db.execute(update(Player).where(Player.id == user.id).values(token_version=1))
    db.commit()
    assert step()["status"] == 401


def test_rollback_keeps_valid_projection(socket_player, db):
    user, _, step, _ = socket_player
    db.get(Player, user.id).is_active = False
    db.flush()
    db.rollback()
    with queries(db) as statements:
        assert step()["type"] == "snapshot"
    assert statements == []


def test_committed_movement_and_block_refresh_other_socket(socket_player, client, account, db):
    user, _, step, _ = socket_player
    other = account("traffic_peer")
    assert client.post("/realtime/enter", headers=other.headers, json={}).status_code == 200
    assert other.id in {p["player_id"] for p in step()["data"]["players"]}
    row = db.get(Presence, other.id)
    row.x += 10
    expected = row.x
    db.commit()
    assert next(p for p in step()["data"]["players"] if p["player_id"] == other.id)["x"] == expected
    db.add(PlayerBlock(player_id=other.id, blocked_id=user.id))
    db.commit()
    reply = step()
    assert other.id not in {p["player_id"] for p in reply["data"]["players"]}
    assert other.id not in {p["player_id"] for p in reply["data"]["proximity"]["nearby"]}


def test_chat_commit_and_expiry_are_visible_without_waiting_full_ttl(socket_player, client, account, db):
    _, protocol, step, now = socket_player
    other = account("traffic_chat")
    client.post("/realtime/enter", headers=other.headers, json={})
    step()
    assert client.post("/realtime/chat", headers=other.headers,
                       json={"body": "hello"}).status_code == 200
    reply = step()
    assert reply["data"]["messages"][0]["body"] == "hello"
    message = db.get(NearbyMessage, reply["data"]["messages"][0]["id"])
    message.expires_at = utcnow() + timedelta(milliseconds=100)
    db.commit()
    step()
    assert 0 < protocol.cache.until - now[0] <= 0.1


def test_disabled_cache_always_queries(socket_player, db, monkeypatch):
    _, protocol, step, _ = socket_player
    monkeypatch.setattr(settings, "realtime_snapshot_cache_seconds", 0)
    protocol.cache.clear()
    step()
    with queries(db) as statements:
        step()
    assert statements
