from datetime import timedelta
from sqlalchemy import select
from app.core.clock import utcnow
from app.core.responses import public
from app.modules.world.service import game_day
from app.modules.progression.models import (
    GoalDefinition,
    GoalProgress,
    PlayerStatistic,
    LoginStreak,
)
from app.modules.economy.service import EconomyService
from app.modules.notifications.service import NotificationsService
from app.db.repository import Repository


class ProgressionService:
    def __init__(self, db):
        self.db, self.repo = db, Repository(db)

    def record(self, player_id, event, quantity=1, now=None):
        # Internal trusted events only; caller owns the player lock and transaction.
        stat = self.repo.get(PlayerStatistic, (player_id, event), False)
        if stat is None:
            stat = self.repo.add(
                PlayerStatistic, player_id=player_id, event=event, value=0
            )
        stat.value += quantity
        period = game_day(self.db, now)
        for goal in self.db.scalars(
            select(GoalDefinition).where(GoalDefinition.event == event)
        ):
            key = (player_id, goal.code, period if goal.kind == "daily" else -1)
            progress = self.repo.get(GoalProgress, key, False)
            if progress is None:
                progress = self.repo.add(
                    GoalProgress,
                    player_id=player_id,
                    goal_code=goal.code,
                    period=key[2],
                    progress=0,
                )
            progress.progress = min(goal.target, progress.progress + quantity)
            if progress.progress >= goal.target and not progress.rewarded:
                progress.rewarded = True
                if goal.aura_reward:
                    EconomyService(self.db).change_internal(
                        player_id,
                        goal.aura_reward,
                        True,
                        goal.kind,
                        "goal",
                        goal.code,
                    )
                NotificationsService(self.db).emit(
                    player_id,
                    goal.kind,
                    f"Completed: {goal.title}",
                    "/progression/goals",
                    f"goal:{goal.code}:{key[2]}",
                )
        self.db.flush()

    def login(self, player_id, now=None):
        today = (now or utcnow()).date()
        row = self.repo.get(LoginStreak, player_id, False)
        if row is None:
            row = self.repo.add(LoginStreak, player_id=player_id, streak=0)
        if row.last_date == today:
            return
        row.streak = row.streak + 1 if row.last_date == today - timedelta(days=1) else 1
        row.last_date = today
        EconomyService(self.db).change_internal(player_id, 10, True, "daily_login")
        self.record(player_id, "login", now=now)

    def goals(self, player_id):
        period = game_day(self.db)
        rows = self.db.execute(
            select(GoalDefinition, GoalProgress).outerjoin(
                GoalProgress,
                (GoalProgress.goal_code == GoalDefinition.code)
                & (GoalProgress.player_id == player_id)
                & (
                    ((GoalDefinition.kind == "daily") & (GoalProgress.period == period))
                    | (
                        (GoalDefinition.kind == "achievement")
                        & (GoalProgress.period == -1)
                    )
                ),
            )
        ).all()
        return {
            "game_day": period,
            "goals": [
                {
                    **public(g),
                    "progress": p.progress if p else 0,
                    "completed": p.rewarded if p else False,
                }
                for g, p in rows
            ],
        }

    def stats(self, player_id):
        row = self.repo.get(LoginStreak, player_id, False)
        streak = (
            row.streak
            if row and row.last_date >= utcnow().date() - timedelta(days=1)
            else 0
        )
        return {
            "login_streak": streak,
            "statistics": {
                r.event: r.value
                for r in self.repo.list(
                    PlayerStatistic, PlayerStatistic.player_id == player_id
                )
            },
        }
