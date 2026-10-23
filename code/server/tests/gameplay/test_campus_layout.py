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
