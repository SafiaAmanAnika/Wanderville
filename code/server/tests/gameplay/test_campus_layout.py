import math
from datetime import timedelta

import pytest

from app.core.clock import utcnow
from app.core.config import settings
from app.modules.realtime import position_projection
from app.modules.realtime.models import Presence
from app.modules.realtime.service import RealtimeService
from app.modules.world.geometry import GEOMETRY, blocked_segment, walkable
from app.modules.world.models import CAMPUS_SPAWN


def test_spawn_has_clear_ground_and_border_contains_it():
    x, y = CAMPUS_SPAWN
    # More than one player-radius of clear ground in every direction.
    assert all(walkable(x+dx, y+dy) for dx in (-100, 0, 100) for dy in (-100, 0, 100))
    assert not walkable(7377, -891)
    assert blocked_segment(x, y, 7377, -891)



def test_collision_polygons_have_no_stray_vertices():
    """A mistyped vertex in map2.tscn must not turn a wall into a spike.

    A stray WaterSource/Collision_top point once exported as a vertex at
    y=37647, a 40,000-unit sliver through the campus. The border wall may wrap
    the boundary slightly; nothing else may leave it, and no vertex may fold
    back on itself between two long edges.
    """
    xs = [x for x, _ in GEOMETRY["boundary"]]
    ys = [y for _, y in GEOMETRY["boundary"]]
    margin = 500.0
    for index, row in enumerate(GEOMETRY["collision"]):
        points = row["points"]
        for x, y in points:
            assert min(xs) - margin <= x <= max(xs) + margin, (index, x, y)
            assert min(ys) - margin <= y <= max(ys) + margin, (index, x, y)
        for k, (bx, by) in enumerate(points):
            (ax, ay), (cx, cy) = points[k - 1], points[(k + 1) % len(points)]
            first, second = (ax - bx, ay - by), (cx - bx, cy - by)
            if min(math.hypot(*first), math.hypot(*second)) < 500.0:
                continue
            turn = abs(math.degrees(
                math.atan2(first[0] * second[1] - first[1] * second[0],
                           first[0] * second[0] + first[1] * second[1])
            ))
            assert turn >= 10.0, ("hairpin vertex", index, k, (bx, by))

@pytest.mark.parametrize("backend", ["database", "memory"])
@pytest.mark.parametrize("saved", [(7377., -891.), (1900., 500.), (1950., 500.)])
def test_reenter_recovers_only_obsolete_positions(account, db, monkeypatch, backend, saved):
    monkeypatch.setattr(settings, "presence_backend", backend)
    user = account()
    row = Presence(player_id=user.id, room="campus", x=saved[0], y=saved[1],
                   sequence=9, room_epoch=2, updated_at=utcnow()-timedelta(seconds=2))
    db.add(row)
    db.commit()
    if backend == "memory":
        position_projection.commit(user.id, row.room, row.x, row.y, row.sequence, row.room_epoch, utcnow())
    result = RealtimeService(db).enter(user.id)
    expected = saved if walkable(*saved) else CAMPUS_SPAWN
    assert (result["x"], result["y"]) == expected
    assert row.sequence == (9 if walkable(*saved) else 0)
    if backend == "memory":
        live = position_projection.get(user.id)
        assert (live.x, live.y) == expected


def test_exported_map_matches_source_scene():
    import importlib.util
    from pathlib import Path
    path = Path(__file__).resolve().parents[2] / "scripts/export_campus_geometry.py"
    spec = importlib.util.spec_from_file_location("campus_export", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert module.export() == GEOMETRY
