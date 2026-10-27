from datetime import timedelta

from sqlalchemy import delete, select

from app.core.clock import as_utc
from app.modules.world.models import PlayerWorld, WorldState
from app.modules.world.service import environment_at, growth_seconds_between


def test_world_isolation_auto_creation_and_protected_mutation(client, account, db):
    first, second = account(), account("player_two")
    one = client.get("/world/me", headers=first.headers).json()["data"]
    two = client.get("/world/me", headers=second.headers).json()["data"]
    assert one["id"] != two["id"]
    assert client.get("/world/me", headers=first.headers).json()["data"] == one
    db.execute(delete(PlayerWorld).where(PlayerWorld.owner_id == first.id))
    db.commit()
    assert (
        client.get("/world/me", headers=first.headers).json()["data"]["owner_id"]
        == first.id
    )
    assert client.post("/world/advance-season").status_code == 401
    assert (
        client.post("/world/advance-season", headers=first.headers).status_code == 403
    )
    assert (
        client.put(
            "/world/tiles", headers=first.headers, json={"tiles": {}}
        ).status_code
        == 410
    )


def test_environment_projection_is_pure_and_crosses_seasons(db):
    state = db.get(WorldState, 1)
    anchor = as_utc(state.season_started_at)
    period = timedelta(minutes=state.season_duration_minutes)
    assert [
        environment_at(state, anchor + period * n).current_season for n in range(5)
    ] == ["summer", "autumn", "winter", "spring", "summer"]
    assert (
        environment_at(state, anchor + timedelta(minutes=10)).current_time_of_day
        == 0.25
    )
    assert not db.dirty
    assert db.get(WorldState, 1).current_season == "summer"
    before = anchor + period - timedelta(seconds=10)
    assert (
        abs(
            growth_seconds_between(state, before, before + timedelta(seconds=20)) - 21.5
        )
        < 0.001
    )


def test_state_does_not_seed_on_get(client, account, db):
    user = account()
    db.execute(delete(WorldState))
    db.commit()
    assert client.get("/world/state", headers=user.headers).status_code == 503
    assert db.scalar(select(WorldState)) is None


def test_all_seasons_expose_server_clock_and_weather(db):
    state = db.get(WorldState, 1)
    anchor = as_utc(state.season_started_at)
    period = timedelta(minutes=state.season_duration_minutes)
    for n in range(8):
        now = anchor + period * n + timedelta(seconds=30)
        result = environment_at(state, now)
        assert result.current_season == ("summer", "autumn", "winter", "spring")[n % 4]
        assert result.server_time == now
        assert result.season_start_time <= now < result.season_end_time
        assert result.season_end_time - result.season_start_time == period
        assert result.weather in {"clear", "rain", "snow"}
        assert result.weather != "snow" or result.current_season == "winter"
