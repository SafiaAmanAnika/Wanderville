"""The movement host's presence bridge: live campus positions reach the roster.

An ENet player never sends a position over the WebSocket, so the presence table
only ever holds the spawn the server committed on entry. Without the bridge every
other player would see them frozen at that spawn. These test the two halves:

* the private ``/internal/multiplayer/presence`` endpoint, which only the host
  may call and which only ever records a *campus* row, into the in-memory
  projection rather than a per-step database write;
* the database-backend roster, which prefers a live projection coordinate for the
  players it is already authorised to show -- and for nobody else.
"""

import pytest

from app.core.config import settings
from app.modules.realtime import position_projection
from app.modules.realtime.models import Presence
from app.modules.realtime.protocol import RealtimeProtocol
from app.modules.realtime.runtime import runtime
from app.modules.world.models import CAMPUS_SPAWN

HOST_SECRET = "host-secret-for-presence-tests"
HOST_HEADERS = {"X-Multiplayer-Secret": HOST_SECRET}


@pytest.fixture(autouse=True)
def host_bridge(monkeypatch):
    monkeypatch.setattr(settings, "multiplayer_bridge_secret", HOST_SECRET)
    # The overlay is a database-backend behaviour; make it explicit rather than
    # depending on the suite's default.
    monkeypatch.setattr(settings, "presence_backend", "database")
    position_projection.reset()
    yield
    position_projection.reset()


def campus_pair(client, account, db):
    a, b = account("enet_presence_a"), account("enet_presence_b")
    for user in (a, b):
        entered = client.post("/realtime/enter", headers=user.headers, json={})
        assert entered.status_code == 200, entered.text
        db.get(Presence, user.id).room = "campus"
        db.commit()
    return a, b


def snapshot_for(db, viewer):
    generation = runtime.attach(viewer.id)
    try:
        reply = RealtimeProtocol(db).step(
            viewer.tokens["access_token"], {"type": "snapshot"}, 2, generation
        )
        assert reply["type"] == "snapshot"
        return reply
    finally:
        runtime.detach(viewer.id, generation)


def player_entry(reply, player_id):
    return next(
        (p for p in reply["data"]["players"] if p["player_id"] == player_id), None
    )


def push(client, updates=(), leaves=()):
    response = client.post(
        "/internal/multiplayer/presence",
        headers=HOST_HEADERS,
        json={"updates": list(updates), "leaves": list(leaves)},
    )
    assert response.status_code == 200, response.text
    return response.json()["data"]


def update(player_id, x, y, sequence=1):
    return {"player_id": player_id, "x": x, "y": y, "sequence": sequence}


# ── the endpoint is host-only ──────────────────────────────────────────────


def test_presence_push_requires_the_host_secret(client):
    assert client.post("/internal/multiplayer/presence", json={"updates": []}).status_code == 403
    assert (
        client.post(
            "/internal/multiplayer/presence",
            headers={"X-Multiplayer-Secret": "wrong"},
            json={"updates": []},
        ).status_code
        == 403
    )


# ── live coordinates win for the roster ────────────────────────────────────


def test_live_position_replaces_the_durable_row_for_a_viewer(client, account, db):
    a, b = campus_pair(client, account, db)
    x, y = CAMPUS_SPAWN[0] + 120.0, CAMPUS_SPAWN[1] - 40.0
    assert push(client, updates=[update(a.id, x, y, sequence=3)])["updated"] == 1

    entry = player_entry(snapshot_for(db, b), a.id)
    assert entry is not None, "the moved player vanished from the roster"
    assert entry["x"] == pytest.approx(x)
    assert entry["y"] == pytest.approx(y)

    # And crucially it was not written to the durable row: an ENet step must not
    # cost a database commit per frame.
    assert db.get(Presence, a.id).x == pytest.approx(CAMPUS_SPAWN[0])


def test_a_viewer_sees_their_own_live_position_too(client, account, db):
    a, b = campus_pair(client, account, db)
    x, y = CAMPUS_SPAWN[0] + 50.0, CAMPUS_SPAWN[1] + 25.0
    push(client, updates=[update(b.id, x, y, sequence=3)])

    entry = player_entry(snapshot_for(db, b), b.id)
    assert entry is not None
    assert entry["x"] == pytest.approx(x)
    assert entry["y"] == pytest.approx(y)


# ── the room comes from the database, never from the host ──────────────────


def test_a_non_campus_row_is_ignored(client, account, db):
    a, b = campus_pair(client, account, db)
    row = db.get(Presence, a.id)
    row.room = "world:1"
    db.commit()

    result = push(client, updates=[update(a.id, 10.0, 10.0)])
    assert result["updated"] == 0 and result["skipped"] == 1
    assert position_projection.get(a.id) is None


def test_an_unknown_player_is_skipped_not_rejected(client, account, db):
    a, b = campus_pair(client, account, db)
    result = push(
        client,
        updates=[update(999999, 1.0, 1.0), update(a.id, 2.0, 2.0)],
    )
    assert result["updated"] == 1 and result["skipped"] == 1


def test_a_leave_drops_the_live_position(client, account, db):
    a, b = campus_pair(client, account, db)
    push(client, updates=[update(a.id, 5.0, 5.0)])
    assert position_projection.get(a.id) is not None

    assert push(client, leaves=[a.id])["left"] == 1
    assert position_projection.get(a.id) is None


# ── the overlay does not disturb a plain database roster ───────────────────


def test_without_a_live_position_the_roster_is_unchanged(client, account, db):
    a, b = campus_pair(client, account, db)
    entry = player_entry(snapshot_for(db, b), a.id)
    assert entry is not None
    assert entry["x"] == pytest.approx(CAMPUS_SPAWN[0])
    assert position_projection.member_ids() == set()
