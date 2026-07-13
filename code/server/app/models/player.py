from __future__ import annotations

from datetime import datetime

from sqlalchemy import Boolean, DateTime, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class Player(Base):
    __tablename__ = "players"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    username: Mapped[str] = mapped_column(String(32), unique=True, index=True, nullable=False)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True, nullable=True)
    hashed_password: Mapped[str] = mapped_column(String(255), nullable=True)
    display_name: Mapped[str] = mapped_column(String(64), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

    email_verified: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    email_verification_token: Mapped[str] = mapped_column(String(255), nullable=True)
    email_verification_expires: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)

    password_reset_token: Mapped[str] = mapped_column(String(255), nullable=True)
    password_reset_expires: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)

    oauth_provider: Mapped[str] = mapped_column(String(32), nullable=True)
    oauth_provider_id: Mapped[str] = mapped_column(String(255), nullable=True)
    avatar_url: Mapped[str] = mapped_column(String(512), nullable=True)

    failed_login_attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    locked_until: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)
    last_login_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)
    last_login_ip: Mapped[str] = mapped_column(String(45), nullable=True)

    position_x: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    position_y: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")

    world = relationship("World", back_populates="owner", uselist=False)
    economy = relationship("PlayerEconomy", back_populates="player", uselist=False)
    experience = relationship("PlayerExperience", back_populates="player", uselist=False)
    inventory_items = relationship("InventoryItem", back_populates="player", cascade="all, delete-orphan")
    farm_plots = relationship("FarmPlot", back_populates="player", cascade="all, delete-orphan")
    refresh_tokens = relationship("RefreshToken", back_populates="player", cascade="all, delete-orphan")
