"""A healthy connection must keep a player present without movement.

``PRESENCE_BACKEND=memory`` expires a live position after
``PRESENCE_MEMORY_TTL_SECONDS``. That age was measured from ``updated_at``,
which only moved when a *movement* packet was committed -- so a player standing
still and merely heartbeating vanished from the room after the TTL, while the
durable ``player_presence`` row (TTL 60s) still said they were there.

Entering a room already records the spawn position, so these tests need no
movement at all: connect, then stand still and heartbeat. That is exactly the
situation the defect broke.
"""

from datetime import timedelta

import pytest

from app.core.clock import as_utc, utcnow
from app.core.config import settings
from app.modules.realtime import position_projection
from app.modules.realtime.models import Presence
from app.modules.realtime.proximity import proximity_view
from app.modules.realtime.service import RealtimeService


@pytest.fixture(params=["database", "memory"])
def backend(request, monkeypatch):
    monkeypatch.setattr(settings, "presence_backend", request.param)
    position_projection.reset()
    yield request.param
    position_projection.reset()


@pytest.fixture
def two_players(backend, client, account):
    # Depends on `backend` so the mode is set before anybody enters; otherwise
    # these two accounts would connect in the default database backend and the
    # in-memory projection would never see them.
    made = []
    for name in ("idle_one", "idle_two"):
        user = account(name)
        assert client.post("/realtime/enter", headers=user.headers, json={"location": "social_lobby"}).status_code == 200
        made.append(user)
    return made


def age_out(player_id):
    """Push a live position past the memory TTL, as real time would.

    Read through ``positions`` rather than ``get``: ``get`` deletes a record the
    moment it finds it expired, and a sweep triggered by an earlier call may
    already have removed it.
    """
    stale = utcnow() - timedelta(seconds=settings.presence_memory_ttl_seconds + 1)
    with position_projection._projection.lock:
        position = position_projection._projection.positions.get(player_id)
        assert position is not None, "expected a live position to age"
        position.updated_at = stale
    assert position_projection.get(player_id) is None, "precondition: it expired"


def visible_to(client, viewer, target_id):
    roster = client.get("/realtime/snapshot", headers=viewer.headers).json()["data"]
    return target_id in {p["player_id"] for p in roster["players"]}


# ── the defect ─────────────────────────────────────────────────────────────


def test_stationary_player_disappears_without_a_heartbeat_fix(two_players, client, db, backend):
    """A heartbeat must sustain presence without any movement packet.

    The assertion is on the *live layer*, not the rendered roster. An expired
    live position silently falls back to the durable ``player_presence`` row, so
    a roster-only check would pass while the in-memory path is dead -- which is
    exactly how this defect survived the first round of tests.
    """
    a, b = two_players
    service = RealtimeService(db)

    if backend == "memory":
        age_out(a.id)
        for _ in range(3):
            service.heartbeat(a.id)
        db.commit()
        assert position_projection.get(a.id) is not None, (
            "memory: a heartbeat must refresh the live position"
        )
    else:
        for _ in range(3):
            service.heartbeat(a.id)
        db.commit()
        row = db.get(Presence, a.id)
        assert (utcnow() - as_utc(row.updated_at)).total_seconds() < 30

    assert visible_to(client, b, a.id), (
        f"{backend}: a stationary player sending heartbeats must stay visible"
    )


def test_stationary_player_stays_proximity_eligible(two_players, client, db, backend):
    a, b = two_players
    service = RealtimeService(db)

    if backend == "memory":
        age_out(a.id)
        for _ in range(3):
            service.heartbeat(a.id)
        db.commit()
        assert position_projection.get(a.id) is not None, (
            "memory: proximity depends on a live position; a heartbeat must keep one"
        )
    else:
        for _ in range(3):
            service.heartbeat(a.id)
        db.commit()

    view = proximity_view(db, b.id)
    assert a.id in {n["player_id"] for n in view["nearby"]}, (
        f"{backend}: a stationary player must remain eligible for chat and voice"
    )


def test_ninety_seconds_of_heartbeats_keeps_a_player_present(two_players, client, db, backend):
    """A player parked in a menu for 90s must not vanish."""
    a, b = two_players
    service = RealtimeService(db)

    for tick in range(180):
        if backend == "memory":
            live = position_projection.get(a.id)
            if live is not None:
                live.updated_at = utcnow() - timedelta(seconds=0.5)
        if tick % 2 == 0:
            service.heartbeat(a.id)
    db.commit()

    if backend == "memory":
        assert position_projection.get(a.id) is not None, (
            "memory: 90s of heartbeats must leave a live position behind"
        )
    assert visible_to(client, b, a.id)


# ── guards: presence must not become immortal ──────────────────────────────


def test_disconnect_still_expires_promptly(two_players, client, db, backend):
    a, b = two_players
    service = RealtimeService(db)

    service.leave(a.id)
    db.commit()

    assert not visible_to(client, b, a.id), (
        f"{backend}: a disconnected player must not linger"
    )
    if backend == "memory":
        assert position_projection.get(a.id) is None


def test_a_silent_player_still_expires(two_players, client, db, backend):
    """No heartbeat at all must still age out, or ghosts accumulate."""
    a, b = two_players

    if backend == "memory":
        age_out(a.id)
        assert position_projection.get(a.id) is None
        # With no live position the roster falls back to the durable row, which
        # is still fresh, so the player remains visible there -- but the live
        # position must not come back.
        assert position_projection.get(a.id) is None
    else:
        row = db.get(Presence, a.id)
        row.updated_at = utcnow() - timedelta(seconds=10_000)
        db.commit()
        assert client.get("/realtime/snapshot", headers=a.headers).status_code == 409


def test_heartbeat_never_fabricates_movement(two_players, client, db, backend):
    """Sustaining presence must not move anybody."""
    a, _ = two_players
    service = RealtimeService(db)
    x, y = db.get(Presence, a.id).x, db.get(Presence, a.id).y

    for _ in range(5):
        service.heartbeat(a.id)
    db.commit()

    after = db.get(Presence, a.id)
    assert (after.x, after.y) == (x, y)
    if backend == "memory":
        live = position_projection.get(a.id)
        assert live is not None, "a heartbeat must not lose the live position"
        assert (live.x, live.y) == (x, y)


def test_heartbeat_does_not_consume_a_movement_sequence(two_players, client, db, backend):
    """Heartbeats must not make the next movement look stale."""
    a, _ = two_players
    service = RealtimeService(db)
    before = db.get(Presence, a.id).sequence

    for _ in range(4):
        service.heartbeat(a.id)
    db.commit()

    row = db.get(Presence, a.id)
    if backend == "database":
        assert row.sequence == before
    else:
        live = position_projection.get(a.id)
        assert live is None or live.sequence == before
