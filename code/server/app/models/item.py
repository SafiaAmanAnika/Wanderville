from __future__ import annotations

from sqlalchemy import Boolean, Index, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class ItemDefinition(Base):
    __tablename__ = "item_definitions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    item_code: Mapped[str] = mapped_column(String(32), unique=True, index=True, nullable=False)
    name: Mapped[str] = mapped_column(String(64), nullable=False)
    category: Mapped[str] = mapped_column(String(32), nullable=False, index=True)
    max_stack: Mapped[int] = mapped_column(Integer, default=99, nullable=False)
    sell_value: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    buy_value: Mapped[int] = mapped_column(Integer, nullable=True)
    growth_time_seconds: Mapped[int] = mapped_column(Integer, nullable=True)
    season: Mapped[str] = mapped_column(String(16), default="all", nullable=False)
    xp_reward: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    rarity: Mapped[str] = mapped_column(String(16), default="common", nullable=False)
    tradable: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    giftable: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    usable: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    placeable: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    icon_path: Mapped[str] = mapped_column(String(255), nullable=True)
    description: Mapped[str] = mapped_column(String(512), nullable=True)

    __table_args__ = (
        Index("ix_item_def_category", "category"),
        Index("ix_item_def_season", "season"),
    )