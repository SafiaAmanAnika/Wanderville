"""Group the SQL a walking player costs, by what it is for.

Reproduce with:

    pytest tests/gameplay/test_presence_baseline.py -q -s

Absolute counts differ between SQLite and PostgreSQL; the shape and the ranking
are the point. Categories are matched against the statement text so a new query
shows up as "other" rather than silently disappearing.
"""

import re
from collections import Counter
from contextlib import contextmanager

import pytest
from sqlalchemy import event

from app.modules.realtime.models import Presence
from app.modules.realtime.service import RealtimeService

CATEGORIES = [
    ("auth", r"players\b.*(token_version|email_verified|is_active)|jwt"),
    ("account lookup", r"FROM players\b"),
    ("world + visit session", r"player_worlds|farm_visit_sessions"),
    ("presence authorization", r"player_presence"),
    ("presence rows", r"FROM player_presence"),
    ("friendship", r"friendships"),
    ("block", r"player_blocks"),
    ("chat", r"nearby_messages|message_recipients|chat_receipts"),
    ("social preferences", r"social_preferences|social_revisions"),
    ("email auth", r"email_verification|auth_tokens"),
    ("session bookkeeping", r"BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE"),
]


def classify(sql):
    flat = " ".join(sql.split())
    for name, pattern in CATEGORIES:
        if re.search(pattern, flat, re.IGNORECASE):
            return name
    return "other"


def group(sql):
    head = flat_head(sql)
    if not head:
        return "other"
    return head.split()[0].upper()


def flat_head(sql):
    return " ".join(sql.split())


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
    def __init__(self, x, y, sequence):
        self.x = x
        self.y = y
        self.sequence = sequence


def measure(db, client, user, steps):
    service = RealtimeService(db)
    row = db.get(Presence, user.id)
    with statements_of(db) as seen:
        for index in range(1, steps + 1):
            service.move(user.id, Step(row.x + 0.5 * index, row.y, row.sequence + index))
            db.commit()
            client.get("/realtime/snapshot", headers=user.headers)
    return seen


@pytest.fixture
def two_on_campus(client, account, db):
    from app.core.rate_limit import limiter

    made = []
    for name in ("base_one", "base_two"):
        limiter.clear()
        user = account(name)
        assert client.post("/realtime/enter", headers=user.headers, json={}).status_code == 200
        made.append(user)
    limiter.clear()
    return made


@pytest.mark.parametrize("mode", ["database", "memory"])
def test_profile_movement_sql(two_on_campus, client, db, monkeypatch, capsys, mode):
    from app.core.config import settings
    from app.modules.realtime import position_projection

    monkeypatch.setattr(settings, "presence_backend", mode)
    position_projection.reset()
    try:
        a, _b = two_on_campus
        seen = measure(db, client, a, steps=10)

        verbs = Counter(group(s) for s in seen)
        by_category = Counter(classify(s) for s in seen)

        with capsys.disabled():
            print(f"\n===== PRESENCE SQL PROFILE ({mode} backend) =====")
            print("10 movement steps + 10 snapshots, 2 players connected")
            print(f"total statements: {len(seen)}")
            print("by verb:")
            for verb, count in verbs.most_common():
                print(f"  {verb:<8} {count}")
            print("by purpose:")
            for name, count in by_category.most_common():
                print(f"  {name:<24} {count}")
            unclassified = Counter(
                " ".join(s.split())[:110] for s in seen if classify(s) == "other"
            )
            if unclassified:
                print("unclassified statement shapes:")
                for shape, count in unclassified.most_common(6):
                    print(f"  [{count:>3}] {shape}")
            print("===========================================")

        assert verbs.get("UPDATE", 0) == (20 if mode == "database" else 0), (
            f"{mode}: unexpected UPDATE count {verbs.get('UPDATE', 0)}"
        )
    finally:
        position_projection.reset()