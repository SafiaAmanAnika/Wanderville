from datetime import datetime

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    Integer,
    String,
    UniqueConstraint,
    false,
    true,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.db.timestamps import Timestamps


class Player(Timestamps, Base):
    __tablename__ = "players"
    __table_args__ = (
        UniqueConstraint("oauth_provider", "oauth_provider_id"),
        CheckConstraint("failed_login_attempts >= 0", name="nonnegative_attempts"),
        CheckConstraint("token_version >= 0", name="nonnegative_token_version"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    username: Mapped[str] = mapped_column(String(32), unique=True)
    email: Mapped[str | None] = mapped_column(String(255), unique=True)
    hashed_password: Mapped[str | None] = mapped_column(String(255))
    display_name: Mapped[str] = mapped_column(String(64))
    is_active: Mapped[bool] = mapped_column(Boolean, server_default=true())
    email_verified: Mapped[bool] = mapped_column(Boolean, server_default=false())
    oauth_provider: Mapped[str | None] = mapped_column(String(32))
    oauth_provider_id: Mapped[str | None] = mapped_column(String(255))
    avatar_url: Mapped[str | None] = mapped_column(String(512))
    failed_login_attempts: Mapped[int] = mapped_column(Integer, server_default="0")
    locked_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_login_ip: Mapped[str | None] = mapped_column(String(45))
    token_version: Mapped[int] = mapped_column(Integer, server_default="0")

    world = relationship(
        "PlayerWorld",
        back_populates="owner",
        uselist=False,
        cascade="all, delete-orphan",
        passive_deletes=True,
    )
    economy = relationship(
        "PlayerEconomy",
        cascade="all, delete-orphan",
        passive_deletes=True,
        uselist=False,
    )
    experience = relationship(
        "PlayerExperience",
        cascade="all, delete-orphan",
        passive_deletes=True,
        uselist=False,
    )
    inventory_items = relationship(
        "InventoryItem", cascade="all, delete-orphan", passive_deletes=True
    )
    refresh_tokens = relationship(
        "RefreshToken", cascade="all, delete-orphan", passive_deletes=True
    )
    account_tokens = relationship(
        "AccountToken", cascade="all, delete-orphan", passive_deletes=True
    )
    transactions = relationship(
        "EconomyTransaction", cascade="all, delete-orphan", passive_deletes=True
    )
