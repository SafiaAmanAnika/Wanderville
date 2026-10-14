from datetime import timedelta

from app.core.clock import as_utc, utcnow
from app.core.config import settings
from app.core.exceptions import AppError, Forbidden, NotFound
from app.db.session import transaction
from app.modules.farming.repository import FarmingRepository
from app.modules.players.repository import PlayerRepository
from app.modules.world.repository import WorldRepository
from app.modules.world.schemas import WorldPublic, WorldStateResponse

SEASONS = ("spring", "summer", "autumn", "winter")


def environment_at(state, now):
    anchor = as_utc(state.season_started_at)
    duration = state.season_duration_minutes * 60
    periods = int((as_utc(now) - anchor).total_seconds() // duration)
    season = SEASONS[(SEASONS.index(state.current_season) + periods) % 4]
    day_seconds = (as_utc(now) - as_utc(state.day_cycle_anchor_at)).total_seconds()
    # Stable periodic weather; explicit stored rain/snow remains an override.
    weather = state.weather
    if (
        weather == "clear"
        and int(day_seconds // (state.day_night_cycle_minutes * 60)) % 4 == 2
    ):
        weather = "snow" if season == "winter" else "rain"
    if weather == "snow" and season != "winter":
        weather = "clear"
    return WorldStateResponse(
        current_season=season,
        season_start_time=anchor + timedelta(seconds=periods * duration),
        season_duration_minutes=state.season_duration_minutes,
        day_night_cycle_minutes=state.day_night_cycle_minutes,
        current_time_of_day=(day_seconds % (state.day_night_cycle_minutes * 60))
        / (state.day_night_cycle_minutes * 60),
        is_raining=weather == "rain",
        weather=weather,
    )


def game_day(db, now=None):
    """Whole day/night cycles elapsed on the shared world clock.

    The authoritative world clock lives on the ``WorldState`` row, so this is
    part of the world domain rather than shared core: ``app/core/`` stays a leaf
    layer with no dependency on any module.
    """
    state = WorldService(db).raw_state()
    return int(
        ((now or utcnow()) - as_utc(state.day_cycle_anchor_at)).total_seconds()
        // (state.day_night_cycle_minutes * 60)
    )


def growth_seconds_between(state, start, end):
    """Integrate seasonal speed across boundaries; complete cycles are O(1)."""
    rates = [getattr(settings, f"farm_{s}_growth_rate") for s in SEASONS]
    offset = SEASONS.index(state.current_season)
    rates = rates[offset:] + rates[:offset]
    duration = state.season_duration_minutes * 60
    anchor = as_utc(state.season_started_at)

    def integral(at):
        seconds = (as_utc(at) - anchor).total_seconds()
        cycles, remaining = divmod(seconds, duration * 4)
        result = cycles * duration * sum(rates)
        for rate in rates:
            part = min(remaining, duration)
            result += part * rate
            remaining -= part
        return result

    return max(0.0, integral(end) - integral(start))


class WorldService:
    def __init__(self, db):
        self.db, self.repo = db, WorldRepository(db)

    def own_world(self, player_id):
        row = self.repo.for_player(player_id)
        if row is None:
            raise NotFound("Player world has not been initialized")
        return row

    def get(self, player_id):
        row = self.repo.for_player(player_id)
        if row is None:
            # Legacy get-or-create contract; serialize missing-world creation.
            with transaction(self.db):
                if not PlayerRepository(self.db).lock(player_id):
                    raise NotFound("Player not found")
                row = self.repo.for_player(player_id) or self.repo.create(player_id)
        return WorldPublic.model_validate(row)

    def raw_state(self):
        row = self.repo.state()
        if row is None:
            raise AppError(
                "SEED_REQUIRED",
                "Initialize reference data with python -m app.db.seed",
                503,
            )
        return row

    def state(self, now=None):
        return environment_at(self.raw_state(), now or utcnow())

    def advance_compatibility(self, now=None):
        if not settings.is_development or not settings.dev_allow_world_mutation:
            raise Forbidden(
                "Season mutation requires the explicit local development switch"
            )
        now = now or utcnow()
        with transaction(self.db):
            row = self.repo.state(lock=True)
            if row is None:
                raise AppError(
                    "SEED_REQUIRED", "Global environment has not been seeded", 503
                )
            if FarmingRepository(self.db).has_active_crops():
                raise AppError(
                    "ACTIVE_CROPS",
                    "Finish or harvest existing crops before forcing a debug season change",
                    409,
                )
            current = environment_at(row, now).current_season
            row.current_season = SEASONS[(SEASONS.index(current) + 1) % 4]
            row.season_started_at = now
            self.db.flush()
            result = environment_at(row, now)
        return result

    @staticmethod
    def retired_tiles():
        raise AppError(
            "LEGACY_WORLD_TILES_REMOVED",
            "Arbitrary map JSON was retired. Use the farming tile API for persisted farm state.",
            410,
        )
