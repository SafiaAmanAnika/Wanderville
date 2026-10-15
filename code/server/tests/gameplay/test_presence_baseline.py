"""Counts the SQL a walking player costs, as a before/after migration probe.

Usage:
    pytest tests/gameplay/test_presence_baseline.py -q -s

The numbers are printed, not asserted, so this file records the measurement
rather than enforcing a budget the optimisation has not reached yet.
"""

from contextlib import contextmanager

import pytest
from sqlalchemy import event

from app.modules.realtime.models import Presence
from app.modules.realtime.protocol import RealtimeProtocol
from app.modules.realtime.runtime import runtime
from app.modules.realtime.service import RealtimeService
from app.modules.world.access import resolve


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


def classify(sql):
    head = " ".join(sql.split()[:6]).upper()
    for kind in ("SELECT", "INSERT", "UPDATE", "DELETE", "BEGIN", "COMMIT"):
        if head.startswith(kind):
            return kind
    return "OTHER"


@pytest.fixture
def walkers(client, account, db):
    """Two players standing on the campus together, both with live sockets."""
    made = []
    for index in range(2):
        user = account(f"walker_{index}")
        assert client.post("/realtime/enter", headers=user.headers, json={}).status_code == 200
        made.append(user)
    yield made
    for user in made:
        runtime.detach(user.id, runtime.attach(user.id))


def test_walking_costs_this_many_statements(walkers, db, capsys):
    a, b = walkers
    service = RealtimeService(db)

    # Put them somewhere unambiguous and a known distance apart.
    for user, x in ((a, 0.0), (b, 300.0)):
        row = db.get(Presence, user.id)
        row.x, row.y = x, 0.0
    db.commit()

    frames = 40  # 40 snapshots == 8 seconds at the client's 5 Hz
    moves = 20  # 20 move packets == 4 seconds of walking at 5 Hz

    with statements_of(db) as seen:
        for step in range(1, moves + 1):
            for user in (a, b):
                row = db.get(Presence, user.id)
                service.move(user.id, type("R", (), {
                    "sequence": row.sequence + step,
                    "x": row.x + 5.0,
                    "y": row.y,
                })())
            db.commit()

        for _ in range(frames):
            for user in (a, b):
                generation = runtime.attach(user.id)
                protocol = RealtimeProtocol(db)
                protocol.step(user.tokens["access_token"], {"type": "snapshot"}, 2, generation)
                runtime.detach(user.id, generation)

    counts = {}
    for sql in seen:
        counts[classify(sql)] = counts.get(classify(sql), 0) + 1

    per_frame_selects = [
        classify(s) == "SELECT" for s in seen
    ]
    roster_queries = [
        s for s in seen
        if "player_presence" in s and "ORDER BY" in s.upper()
    ]

    with capsys.disabled():
        print("\n===== presence SQL baseline =====")
        print(f"players                     : {len(walkers)}")
        print(f"move packets                : {moves}")
        print(f"snapshot frames             : {frames}")
        print(f"total statements            : {len(seen)}")
        for kind in sorted(counts):
            print(f"  {kind:<8}: {counts[kind]}")
        print(f"roster distance queries     : {len(roster_queries)}")
        print(f"statements per snapshot     : {len(seen) / (frames * len(walkers)):.1f}")
        print(f"presence UPDATE statements  : {counts.get('UPDATE', 0)}")
        print("================================")