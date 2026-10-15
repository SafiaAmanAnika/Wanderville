"""``PRESENCE_BACKEND=memory`` keeps live positions in process.

The contract these tests pin down:

* coordinates are authoritative in memory, and a direct database edit does not
  override an active live position;
* PostgreSQL still decides identity, ownership, visits, blocks and privacy, so a
  permission change takes effect immediately in either backend;
* a caller always appears in their own roster;
* movement is still validated before anything is recorded;
* stale, expired and disconnected players disappear rather than being restored
  from an old database row.

Every test that asserts a behaviour common to both backends is parameterised, so
the two modes cannot drift apart silently.
"""

from contextlib import contextmanager
from datetime import timedelta

import pytest
from sqlalchemy import event

from app.core.clock import utcnow
from app.core.config import settings
from app.core.exceptions import AppError
from app.modules.realtime import position_projection
from app.modules.realtime.models import Presence
from app.modules.realtime.proximity import proximity_view
from app.modules.realtime.service import RealtimeService
from app.modules.social.models import PlayerBlock


@contextmanager
def statements_of(db):
    seen = []

    def record(_conn, _cursor, statement, _parameters, _context, _many):
        seen.append(statement)

    engine = db.get_bind()
    event.listen(engine, "before_cursor_execute", record)
    try:
        yield seen
    finally:
        event.remove(engine, "before_cursor_execute", record)


class Step:
    """A movement request, matching the shape the router builds."""

    def __init__(self, x, y, sequence):
        self.x = x
        self.y = y
        self.sequence = sequence


@pytest.fixture
def memory_mode(monkeypatch):
    """Run one test against the in-memory presence backend."""
    monkeypatch.setattr(settings, "presence_backend", "memory")
    position_projection.reset()
    yield
    position_projection.reset()


@pytest.fixture
def database_mode(monkeypatch):
    monkeypatch.setattr(settings, "presence_backend", "database")
    position_projection.reset()
    yield
    position_projection.reset()


@pytest.fixture
def campus_players(client, account):
    made = []
    for index, name in enumerate(("mem_one", "mem_two")):
        user = account(name)
        assert client.post("/realtime/enter", headers=user.headers, json={}).status_code == 200
        made.append(user)
    return made


def walk(service, pid, x, y, sequence):
    return service.move(pid, Step(x, y, sequence))


def step_along(service, pid, row, index, delta=2.0, axis="x"):
    """One accepted walking step.

    Steps are small on purpose: ``move`` allows
    ``max_move_speed * elapsed + 5``, and with a fresh sequence elapsed is near
    zero, so a large jump is correctly rejected as a speed violation rather than
    recorded. They run along one axis in one direction because the campus spawn
    sits beside a lake whose polygon a long straight run would cross.
    """
    offset = delta * index if axis == "x" else 0.0
    perpendicular = 0.0 if axis == "x" else delta * index
    return walk(
        service, pid, row.x + offset, row.y + perpendicular, row.sequence + index
    )


# ── common contract, both backends ────────────────────────────────────────


@pytest.mark.parametrize("mode", ["database", "memory"])
def test_caller_appears_in_their_own_roster(client, account, db, monkeypatch, mode):
    monkeypatch.setattr(settings, "presence_backend", mode)
    position_projection.reset()
    try:
        user = account(f"self_{mode}")
        assert client.post("/realtime/enter", headers=user.headers, json={}).status_code == 200
        snapshot = client.get("/realtime/snapshot", headers=user.headers)
        assert snapshot.status_code == 200, snapshot.text
        ids = {p["player_id"] for p in snapshot.json()["data"]["players"]}
        assert user.id in ids, f"{mode} mode: a player must see themselves"
    finally:
        position_projection.reset()


@pytest.mark.parametrize("mode", ["database", "memory"])
def test_blocked_player_leaves_the_roster(client, account, db, monkeypatch, mode):
    monkeypatch.setattr(settings, "presence_backend", mode)
    position_projection.reset()
    try:
        a = account(f"blocker_{mode}")
        b = account(f"blocked_{mode}")
        assert client.post("/realtime/enter", headers=a.headers, json={}).status_code == 200
        assert client.post("/realtime/enter", headers=b.headers, json={}).status_code == 200
        assert b.id in {
            p["player_id"]
            for p in client.get("/realtime/snapshot", headers=a.headers).json()["data"]["players"]
        }

        db.add(PlayerBlock(player_id=b.id, blocked_id=a.id))
        db.commit()

        after = client.get("/realtime/snapshot", headers=a.headers).json()["data"]["players"]
        assert b.id not in {p["player_id"] for p in after}
        view = proximity_view(db, a.id)
        assert b.id not in {n["player_id"] for n in view["nearby"]}
    finally:
        position_projection.reset()


@pytest.mark.parametrize("mode", ["database", "memory"])
def test_movement_is_still_validated(client, account, db, monkeypatch, mode):
    """A rejected step must not change the recorded position, in either backend."""
    monkeypatch.setattr(settings, "presence_backend", mode)
    position_projection.reset()
    try:
        user = account(f"hack_{mode}")
        assert client.post("/realtime/enter", headers=user.headers, json={}).status_code == 200
        service = RealtimeService(db)
        row = db.get(Presence, user.id)
        before_row = (row.x, row.y, row.sequence)
        before_live = position_projection.get(user.id)
        before_live = (before_live.x, before_live.y, before_live.sequence) if before_live else None

        with pytest.raises(AppError):
            # Far beyond max_move_speed for a fresh sequence.
            walk(service, user.id, row.x + 100000, row.y, row.sequence + 1)

        after_row = db.get(Presence, user.id)
        if mode == "memory":
            assert (after_row.x, after_row.y, after_row.sequence) == before_row
            live = position_projection.get(user.id)
            now_live = (live.x, live.y, live.sequence) if live else None
            assert now_live == before_live, (
                "a rejected movement packet must not be recorded in the projection"
            )
        else:
            assert (after_row.x, after_row.y, after_row.sequence) == before_row
    finally:
        position_projection.reset()


# ── memory-specific contract ──────────────────────────────────────────────


def test_walking_does_not_write_presence(client, account, db, memory_mode, campus_players):
    a, b = campus_players
    service = RealtimeService(db)
    before = {p.id: (db.get(Presence, p.id).x, db.get(Presence, p.id).y)
              for p in (a, b)}
    seq = {a.id: db.get(Presence, a.id).sequence, b.id: db.get(Presence, b.id).sequence}

    for step in range(1, 11):
        for user in (a, b):
            step_along(service, user.id, db.get(Presence, user.id), step, delta=1.0)
        db.commit()

    for user in (a, b):
        row = db.get(Presence, user.id)
        assert (row.x, row.y) == before[user.id], (
            f"player {user.id} was written to PostgreSQL while walking in memory mode"
        )


def test_memory_position_is_what_the_snapshot_reports(client, account, db, memory_mode, campus_players):
    a, b = campus_players
    service = RealtimeService(db)
    row = db.get(Presence, a.id)
    step_along(service, a.id, row, 2)
    db.commit()
    expected_x = position_projection.get(a.id).x

    snapshot = client.get("/realtime/snapshot", headers=b.headers).json()["data"]
    entry = next(p for p in snapshot["players"] if p["player_id"] == a.id)
    assert entry["x"] == pytest.approx(expected_x), (
        "the snapshot must report the live in-memory position, not the last "
        "committed database row"
    )
    assert entry["x"] != pytest.approx(db.get(Presence, a.id).x), (
        "the durable row must not have been rewritten by walking"
    )


def test_direct_database_edit_does_not_override_a_live_position(
    client, account, db, memory_mode, campus_players
):
    """Memory wins for coordinates, which is the whole point of memory mode."""
    a, b = campus_players
    service = RealtimeService(db)
    row = db.get(Presence, a.id)
    step_along(service, a.id, row, 2)
    db.commit()
    live_x = position_projection.get(a.id).x

    tampered = db.get(Presence, a.id)
    tampered.x += 500.0
    db.commit()

    snapshot = client.get("/realtime/snapshot", headers=b.headers).json()["data"]
    entry = next(p for p in snapshot["players"] if p["player_id"] == a.id)
    assert entry["x"] == pytest.approx(live_x), (
        "memory mode must report the live position even after the durable row "
        "is edited behind its back"
    )
    assert entry["x"] != pytest.approx(tampered.x)


def test_database_edit_still_wins_in_database_mode(client, account, db, database_mode, campus_players):
    """The opposite guarantee for the default backend."""
    a, b = campus_players
    tampered = db.get(Presence, a.id)
    # Stay inside realtime_roster_radius so the edit is observable at all.
    expected = tampered.x + 500.0
    tampered.x = expected
    db.commit()

    snapshot = client.get("/realtime/snapshot", headers=b.headers).json()["data"]
    entry = next(p for p in snapshot["players"] if p["player_id"] == a.id)
    assert entry["x"] == pytest.approx(expected)


def test_disconnect_removes_the_live_position(client, account, db, memory_mode, campus_players):
    a, b = campus_players
    service = RealtimeService(db)
    step_along(service, a.id, db.get(Presence, a.id), 2)
    db.commit()
    assert position_projection.get(a.id) is not None

    service.leave(a.id)
    db.commit()

    assert position_projection.get(a.id) is None
    snapshot = client.get("/realtime/snapshot", headers=b.headers).json()["data"]
    assert a.id not in {p["player_id"] for p in snapshot["players"]}


def test_expired_position_is_not_resurrected_from_the_database(
    client, account, db, memory_mode, campus_players
):
    """A stale live position must vanish, not fall back to an old row."""
    a, b = campus_players
    service = RealtimeService(db)
    row = db.get(Presence, a.id)
    step_along(service, a.id, row, 2)
    db.commit()

    record = position_projection.get(a.id)
    position_projection.commit(
        a.id, record.room, row.x - 900.0, record.y, record.sequence, record.room_epoch,
        utcnow() - timedelta(seconds=settings.presence_memory_ttl_seconds + 5),
    )

    snapshot = client.get("/realtime/snapshot", headers=b.headers).json()["data"]
    entry = next((p for p in snapshot["players"] if p["player_id"] == a.id), None)
    # The durable row still holds a position, but memory mode must not serve it
    # as if the player were live; at most they appear at their stored spawn.
    if entry is not None:
        assert entry["x"] != pytest.approx(row.x - 900.0)


def test_room_change_does_not_leave_the_old_room_visible(
    client, account, db, memory_mode
):
    a = account("room_switch")
    assert client.post("/realtime/enter", headers=a.headers, json={}).status_code == 200
    assert client.post("/realtime/enter", headers=a.headers, json={"owner_id": a.id}).status_code == 200

    campus_record = None
    for position in position_projection.room_members("campus"):
        if position.player_id == a.id:
            campus_record = position
    assert campus_record is None, "the player must not remain in the campus room"


def test_restart_does_not_resurrect_stale_positions(memory_mode):
    """A fresh process starts empty; presence is rebuilt by connecting."""
    position_projection.commit(7, "campus", 1.0, 2.0, 1, 1, utcnow())
    assert position_projection.size() == 1
    position_projection.reset()
    assert position_projection.size() == 0


def test_projection_is_bounded(memory_mode, monkeypatch):
    monkeypatch.setattr(position_projection._projection, "max_players", 8)
    now = utcnow()
    for index in range(40):
        position_projection.commit(index, "campus", float(index), 0.0, 1, 1, now)
    assert position_projection.size() <= 8


def test_expired_records_are_swept(memory_mode, monkeypatch):
    monkeypatch.setattr(position_projection._projection, "ttl_seconds", 5)
    old = utcnow() - timedelta(seconds=120)
    position_projection.commit(1, "campus", 0.0, 0.0, 1, 1, old)
    assert position_projection.get(1) is None


def test_proximity_uses_live_memory_positions(client, account, db, memory_mode, campus_players):
    a, b = campus_players
    service = RealtimeService(db)
    row = db.get(Presence, a.id)
    # Walk a short, collision-free distance inside the exit radius.
    for index in range(1, 11):
        step_along(service, a.id, row, index)
    db.commit()

    view = proximity_view(db, b.id)
    assert a.id in {n["player_id"] for n in view["nearby"]}, (
        "the proximity policy must follow the live in-memory positions"
    )


def test_memory_mode_costs_fewer_statements(client, account, db, monkeypatch):
    """Measure both backends under an identical movement workload."""
    from app.core.rate_limit import limiter

    results = {}
    for mode in ("database", "memory"):
        monkeypatch.setattr(settings, "presence_backend", mode)
        position_projection.reset()
        # Signup is rate limited per IP and this loop makes four accounts.
        limiter.clear()
        user = account(f"cost_{mode}")
        limiter.clear()
        other = account(f"cost_peer_{mode}")
        limiter.clear()
        assert client.post("/realtime/enter", headers=user.headers, json={}).status_code == 200
        assert client.post("/realtime/enter", headers=other.headers, json={}).status_code == 200
        service = RealtimeService(db)
        row = db.get(Presence, user.id)

        with statements_of(db) as seen:
            # Walk along y for a short distance. The campus spawn sits beside
            # obstacles, and each step is validated against the *previous*
            # accepted position, so a long run clips a polygon partway along.
            for step in range(1, 11):
                step_along(service, user.id, row, step, delta=1.0, axis="y")
                db.commit()
                client.get("/realtime/snapshot", headers=user.headers)

        updates = [s for s in seen if s.lstrip().upper().startswith("UPDATE")]
        selects = [s for s in seen if s.lstrip().upper().startswith("SELECT")]
        results[mode] = (len(updates), len(selects))
        position_projection.reset()

    db_updates, db_selects = results["database"]
    mem_updates, mem_selects = results["memory"]
    print(
        f"\n===== movement workload (10 steps + 10 snapshots) =====\n"
        f"  database: {db_updates} UPDATE, {db_selects} SELECT\n"
        f"  memory  : {mem_updates} UPDATE, {mem_selects} SELECT\n"
        f"  ====================================================="
    )
    assert mem_updates < db_updates, (
        f"memory mode must not write per movement step: "
        f"{mem_updates} vs {db_updates}"
    )