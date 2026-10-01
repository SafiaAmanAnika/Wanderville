from datetime import date
from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Date,
    ForeignKey,
    Integer,
    String,
    false,
)
from sqlalchemy.orm import Mapped, mapped_column
from app.db.base import Base


class GoalDefinition(Base):
    __tablename__ = "goal_definitions"
    __table_args__ = (
        CheckConstraint("target > 0 AND aura_reward >= 0", name="goal_values"),
        CheckConstraint("kind IN ('achievement','daily')", name="kind"),
    )
    code: Mapped[str] = mapped_column(String(32), primary_key=True)
    kind: Mapped[str] = mapped_column(String(16))
    title: Mapped[str] = mapped_column(String(128))
    event: Mapped[str] = mapped_column(String(32), index=True)
    target: Mapped[int] = mapped_column(Integer)
    aura_reward: Mapped[int] = mapped_column(Integer)


class GoalProgress(Base):
    __tablename__ = "goal_progress"
    __table_args__ = (CheckConstraint("progress >= 0", name="progress"),)
    player_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), primary_key=True
    )
    goal_code: Mapped[str] = mapped_column(
        ForeignKey("goal_definitions.code"), primary_key=True
    )
    period: Mapped[int] = mapped_column(Integer, primary_key=True)
    progress: Mapped[int] = mapped_column(Integer, server_default="0")
    rewarded: Mapped[bool] = mapped_column(Boolean, server_default=false())


class PlayerStatistic(Base):
    __tablename__ = "player_statistics"
    __table_args__ = (CheckConstraint("value >= 0", name="value"),)
    player_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), primary_key=True
    )
    event: Mapped[str] = mapped_column(String(32), primary_key=True)
    value: Mapped[int] = mapped_column(Integer, server_default="0")


class LoginStreak(Base):
    __tablename__ = "login_streaks"
    __table_args__ = (CheckConstraint("streak >= 0", name="streak"),)
    player_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), primary_key=True
    )
    last_date: Mapped[date | None] = mapped_column(Date)
    streak: Mapped[int] = mapped_column(Integer, server_default="0")
