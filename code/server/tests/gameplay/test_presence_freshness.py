"""A cached snapshot must never serve coordinates that are already out of date.

``PRESENCE_BACKEND=memory`` writes no ``player_presence`` row when a player
moves, so the cache invalidation that is driven by database commits
(``snapshot_revision``) never fires for movement. The per-connection passive
cache keys on ``(token, protocol, generation)``, so it is safe for the viewer it
was built for -- but a *viewer* must not be handed another player's stale
position either, and the roster has to reflect the newest accepted movement.
"""

import pytest

from app.core.clock import as_utc, utcnow
from app.core.config import settings
from app.modules.realtime import position_projection
from app.modules.realtime.models import Presence
from app.modules.realtime.protocol import RealtimeProtocol
from app.modules.realtime.runtime import runtime
from app.modules.realtime.service import RealtimeService


class Step:
    def __init__(self, x, y, sequence):
        self.x = x
        self.y = y
        self.sequence = sequence


@pytest.fixture
def memory_mode(monkeypatch):
    monkeypatch.setattr(settings, "presence_backend", "memory")
    monkeypatch.setattr(settings, "realtime_snapshot_cache_seconds", 1.0)
    position_projection.reset()
    yield
    position_projection.reset()


@pytest.fixture
def pair(client, account):
    a, b = account("cache_a"), account("cache_b")
    for user in (a, b):
        assert client.post("/realtime/enter", headers=user.headers, json={"location": "social_lobby"}).status_code == 200
    return a, b


def viewer_snapshot(db, viewer):
    generation = runtime.attach(viewer.id)
    try:
        reply = RealtimeProtocol(db).step(
            viewer.tokens["access_token"], {"type": "snapshot"}, 2, generation
        )
        assert reply["type"] == "snapshot"
        return reply
    finally:
        runtime.detach(viewer.id, generation)


def position_of(reply, player_id):
    return next(
        (p for p in reply["data"]["players"] if p["player_id"] == player_id), None
    )


def move_a(service, a, db, row, index, delta=0.5):
    """Advance player A by one accepted step.

    ``move`` allows ``max_move_speed * elapsed + 5``, and a freshly committed
    step leaves almost no elapsed time, so the budget is only a few units. A
    sub-unit step keeps these tests about freshness rather than about the speed
    limiter.
    """
    service.move(a.id, Step(row.x + delta * index, row.y, row.sequence + index))
    db.commit()


def test_a_viewer_sees_the_latest_movement_not_a_cached_one(pair, client, db, memory_mode):
    a, b = pair
    service = RealtimeService(db)
    row = db.get(Presence, a.id)

    first = viewer_snapshot(db, b)
    original = position_of(first, a.id)["x"]

    move_a(service, a, db, row, 1, delta=0.5)
    expected = position_projection.get(a.id).x
    assert expected != original

    second = viewer_snapshot(db, b)
    assert position_of(second, a.id)["x"] == pytest.approx(expected), (
        "a viewer must see the newest accepted position, not a cached one"
    )


def test_rapid_consecutive_moves_converge_on_the_latest(pair, client, db, memory_mode):
    a, b = pair
    service = RealtimeService(db)
    row = db.get(Presence, a.id)

    for index in range(1, 6):
        move_a(service, a, db, row, index, delta=0.5)
        viewer_snapshot(db, b)  # a frame between every step, as a real socket does

    expected = position_projection.get(a.id).x
    final = viewer_snapshot(db, b)
    assert position_of(final, a.id)["x"] == pytest.approx(expected)


def test_two_players_moving_at_once_are_both_current(pair, client, db, memory_mode):
    a, b = pair
    service = RealtimeService(db)
    row_a = db.get(Presence, a.id)
    row_b = db.get(Presence, b.id)

    for index in range(1, 4):
        move_a(service, a, db, row_a, index, delta=0.5)
        service.move(b.id, Step(row_b.x - 0.5 * index, row_b.y, row_b.sequence + index))
        db.commit()

    reply = viewer_snapshot(db, b)
    assert position_of(reply, a.id)["x"] == pytest.approx(
        position_projection.get(a.id).x
    )
    own = position_of(reply, b.id)
    assert own is not None and own["x"] == pytest.approx(
        position_projection.get(b.id).x
    )


def test_a_stale_coordinate_never_overwrites_a_newer_one(pair, client, db, memory_mode):
    """An old frame must not roll the projection backwards."""
    a, b = pair
    service = RealtimeService(db)
    row = db.get(Presence, a.id)

    move_a(service, a, db, row, 1, delta=0.5)
    newest = position_projection.get(a.id)
    newest_x, newest_seq = newest.x, newest.sequence

    from app.core.exceptions import AppError

    with pytest.raises(AppError):
        # An older sequence must be refused outright.
        service.move(a.id, Step(newest_x - 100.0, newest.y, newest_seq - 1))
    db.commit()

    live = position_projection.get(a.id)
    assert (live.x, live.sequence) == (newest_x, newest_seq)


def test_reconnect_sees_one_copy_of_each_player(pair, client, db, memory_mode):
    a, b = pair
    reply = viewer_snapshot(db, b)
    ids = [p["player_id"] for p in reply["data"]["players"]]
    assert sorted(ids) == sorted(set(ids)), "the roster must not contain duplicates"
    assert ids.count(a.id) == 1


def test_disconnect_removes_the_peer_from_the_next_frame(pair, client, db, memory_mode):
    a, b = pair
    viewer_snapshot(db, b)

    RealtimeService(db).leave(a.id)
    db.commit()

    assert position_projection.get(a.id) is None
    reply = viewer_snapshot(db, b)
    assert position_of(reply, a.id) is None, (
        "a disconnected player must not linger in a cached roster"
    )


def test_room_change_invalidates_the_cached_room(pair, client, db, memory_mode):
    """A player who changes room must be reported in the new room immediately.

    The expected room uses the player's own world *id*, never their player id.
    The two coincide on a fresh SQLite database but not once sequences drift --
    which is exactly what happens on PostgreSQL, and what commit 1968519 fixed.
    """
    from app.modules.world.access import owned_world

    a, b = pair
    reply = viewer_snapshot(db, b)
    assert reply["data"]["room"] == "social_lobby"

    assert client.post(
        "/realtime/enter", headers=b.headers, json={"owner_id": b.id}
    ).status_code == 200
    db.commit()

    moved = viewer_snapshot(db, b)
    assert moved["data"]["room"] == f"world:{owned_world(db, b.id).id}"
    assert moved["data"]["room"] != "social_lobby"


def test_block_takes_effect_despite_an_active_cache(pair, client, db, memory_mode):
    from app.modules.social.models import PlayerBlock

    a, b = pair
    assert position_of(viewer_snapshot(db, b), a.id) is not None

    db.add(PlayerBlock(player_id=a.id, blocked_id=b.id))
    db.commit()

    assert position_of(viewer_snapshot(db, b), a.id) is None, (
        "a block must hide the player even while a passive cache is warm"
    )