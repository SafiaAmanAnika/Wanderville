# Legacy backend audit

Source: uploaded working tree before refactoring. No connection was made to an existing database.

## Migration chain

- `001_initial_schema.py`: `None` -> `001_initial_schema`
- `002_add_world_table.py`: `001_initial_schema` -> `002_add_world_table`
- `003_add_fk_cascade.py`: `002_add_world_table` -> `003_add_fk_cascade`
- `004_add_persistence_layer.py`: `fe33f4e10006` -> `004_add_persistence_layer`
- `005_add_auth_upgrade.py`: `004_add_persistence_layer` -> `005_add_auth_upgrade`
- `39e5dd4b1af7_add_farm_plots_table.py`: `003_add_fk_cascade` -> `39e5dd4b1af7`
- `fe33f4e10006_add_inventory_items_table.py`: `39e5dd4b1af7` -> `fe33f4e10006`

Head: `005_add_auth_upgrade` (one linear chain of seven revisions).

## Existing model declarations

### economy.py

```python
from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import ForeignKey, Integer
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class PlayerEconomy(Base):
    __tablename__ = "player_economy"

    player_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("players.id", ondelete="CASCADE"),
        primary_key=True,
    )
    taka_balance: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    coin_balance: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    total_earned: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    total_spent: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )

    player = relationship("Player", back_populates="economy")
```

### experience.py

```python
from __future__ import annotations

from sqlalchemy import ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class PlayerExperience(Base):
    __tablename__ = "player_experience"

    player_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("players.id", ondelete="CASCADE"),
        primary_key=True,
    )
    current_xp: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    total_xp: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    level: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    xp_to_next_level: Mapped[int] = mapped_column(Integer, default=100, nullable=False)
    title: Mapped[str] = mapped_column(String(64), nullable=True)

    player = relationship("Player", back_populates="experience")
```

### farm.py

```python
from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class FarmPlot(Base):
    __tablename__ = "farm_plots"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    player_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("players.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    x: Mapped[int] = mapped_column(Integer, nullable=False)
    y: Mapped[int] = mapped_column(Integer, nullable=False)
    item_code: Mapped[str] = mapped_column(
        String(32),
        ForeignKey("item_definitions.item_code"),
        nullable=True,
    )
    planted_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)
    growth_stage: Mapped[int] = mapped_column(Integer, default=0)
    is_watered: Mapped[bool] = mapped_column(Boolean, default=False)
    is_harvested: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
    )

    player = relationship("Player", back_populates="farm_plots")
    item = relationship("ItemDefinition", lazy="joined")

    MAX_STAGES = 3

    def is_ready_for_harvest(self) -> bool:
        return self.growth_stage >= self.MAX_STAGES and not self.is_harvested

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "x": self.x,
            "y": self.y,
            "item_code": self.item_code,
            "growth_stage": self.growth_stage,
            "is_watered": self.is_watered,
            "is_harvested": self.is_harvested,
            "planted_at": self.planted_at.isoformat() if self.planted_at else None,
            "ready": self.is_ready_for_harvest(),
        }
```

### inventory.py

```python
from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import ForeignKey, Index, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class InventoryItem(Base):
    __tablename__ = "inventory_items"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    player_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("players.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    item_code: Mapped[str] = mapped_column(
        String(32),
        ForeignKey("item_definitions.item_code"),
        nullable=False,
    )
    quantity: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    slot_index: Mapped[int] = mapped_column(Integer, nullable=True)
    location: Mapped[str] = mapped_column(String(16), default="inventory", nullable=False)

    created_at: Mapped[datetime] = mapped_column(default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )

    __table_args__ = (
        UniqueConstraint("player_id", "item_code", "location", name="uix_player_item_location"),
        Index("ix_inventory_player_location", "player_id", "location"),
    )

    item = relationship("ItemDefinition", lazy="joined")
    player = relationship("Player", back_populates="inventory_items")
```

### item.py

```python
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
```

### player.py

```python
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
```

### refresh_token.py

```python
from __future__ import annotations

from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class RefreshToken(Base):
    __tablename__ = "refresh_tokens"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    token_hash: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    player_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("players.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    device_info: Mapped[str] = mapped_column(String(255), nullable=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

    player = relationship("Player", back_populates="refresh_tokens")
```

### world.py

```python
from __future__ import annotations

from datetime import datetime

from sqlalchemy import JSON, Boolean, DateTime, Float, ForeignKey, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class World(Base):
    __tablename__ = "worlds"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    owner_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("players.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    name: Mapped[str] = mapped_column(String(64), nullable=False, default="My World")
    tiles: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

    owner = relationship("Player", back_populates="world")


class WorldState(Base):
    __tablename__ = "world_state"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    current_season: Mapped[str] = mapped_column(String(16), default="summer", nullable=False)
    season_start_time: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)
    season_duration_minutes: Mapped[int] = mapped_column(Integer, default=10080, nullable=False)
    day_night_cycle_minutes: Mapped[int] = mapped_column(Integer, default=40, nullable=False)
    current_time_of_day: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    is_raining: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    last_updated: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
    )
```

## Catalog before refactor

```python
[
    # General Purpose Crops
    {"item_code": "paddy", "name": "Paddy", "category": "general_crop", "growth_time_seconds": 30, "sell_value": 10, "xp_reward": 5, "season": "all"},
    {"item_code": "wheat", "name": "Wheat", "category": "general_crop", "growth_time_seconds": 45, "sell_value": 12, "xp_reward": 5, "season": "all"},
    {"item_code": "sugarcane", "name": "Sugarcane", "category": "general_crop", "growth_time_seconds": 50, "sell_value": 15, "xp_reward": 5, "season": "all"},
    {"item_code": "corn", "name": "Corn", "category": "general_crop", "growth_time_seconds": 170, "sell_value": 20, "xp_reward": 8, "season": "summer"},
    {"item_code": "cotton", "name": "Cotton", "category": "general_crop", "growth_time_seconds": 140, "sell_value": 18, "xp_reward": 8, "season": "summer"},
    # Summer
    {"item_code": "sweet_corn", "name": "Sweet Corn", "category": "summer_crop", "growth_time_seconds": 180, "sell_value": 25, "xp_reward": 10, "season": "summer"},
    {"item_code": "bell_pepper", "name": "Bell Pepper", "category": "summer_crop", "growth_time_seconds": 150, "sell_value": 22, "xp_reward": 10, "season": "summer"},
    {"item_code": "green_bean", "name": "Green Bean", "category": "summer_crop", "growth_time_seconds": 120, "sell_value": 18, "xp_reward": 10, "season": "summer"},
    # Autumn
    {"item_code": "pumpkin", "name": "Pumpkin", "category": "autumn_crop", "growth_time_seconds": 200, "sell_value": 30, "xp_reward": 10, "season": "autumn"},
    {"item_code": "apple", "name": "Apple", "category": "autumn_crop", "growth_time_seconds": 300, "sell_value": 35, "xp_reward": 10, "season": "autumn"},
    {"item_code": "turnip", "name": "Turnip", "category": "autumn_crop", "growth_time_seconds": 140, "sell_value": 15, "xp_reward": 10, "season": "autumn"},
    # Winter
    {"item_code": "potato", "name": "Potato", "category": "winter_crop", "growth_time_seconds": 220, "sell_value": 20, "xp_reward": 10, "season": "winter"},
    {"item_code": "carrot", "name": "Carrot", "category": "winter_crop", "growth_time_seconds": 160, "sell_value": 16, "xp_reward": 10, "season": "winter"},
    {"item_code": "cabbage", "name": "Cabbage", "category": "winter_crop", "growth_time_seconds": 190, "sell_value": 18, "xp_reward": 10, "season": "winter"},
    {"item_code": "strawberry", "name": "Strawberry", "category": "winter_crop", "growth_time_seconds": 240, "sell_value": 28, "xp_reward": 10, "season": "winter"},
    # Spring
    {"item_code": "lettuce", "name": "Lettuce", "category": "spring_crop", "growth_time_seconds": 100, "sell_value": 14, "xp_reward": 10, "season": "spring"},
    {"item_code": "pea", "name": "Pea", "category": "spring_crop", "growth_time_seconds": 130, "sell_value": 16, "xp_reward": 10, "season": "spring"},
    {"item_code": "radish", "name": "Radish", "category": "spring_crop", "growth_time_seconds": 90, "sell_value": 12, "xp_reward": 10, "season": "spring"},
    # Rare Plants
    {"item_code": "moonflower", "name": "Moonflower", "category": "rare_plant", "growth_time_seconds": 600, "sell_value": 100, "xp_reward": 30, "season": "all", "rarity": "rare"},
    {"item_code": "rivermint", "name": "Rivermint", "category": "rare_plant", "growth_time_seconds": 480, "sell_value": 80, "xp_reward": 25, "season": "all", "rarity": "rare"},
    {"item_code": "sunbloom", "name": "Sunbloom", "category": "rare_plant", "growth_time_seconds": 540, "sell_value": 90, "xp_reward": 25, "season": "all", "rarity": "rare"},
    {"item_code": "ancient_grain", "name": "Ancient Grain", "category": "rare_plant", "growth_time_seconds": 720, "sell_value": 120, "xp_reward": 30, "season": "all", "rarity": "epic"},
]
```

## Route inventory

- POST /auth/signup
- POST /auth/login
- POST /auth/google
- POST /auth/refresh
- POST /auth/logout
- GET /auth/verify-email
- POST /auth/resend-verification
- POST /auth/forgot-password
- POST /auth/reset-password
- PUT /auth/change-password
- GET /auth/me
- GET /economy/
- POST /economy/earn
- POST /economy/spend
- GET /economy/xp
- POST /economy/xp/gain
- GET /farm/plots
- POST /farm/plant
- POST /farm/water
- POST /farm/harvest
- GET /health
- GET /inventory/
- GET /inventory/catalog
- GET /inventory/catalog/{season}
- POST /inventory/add
- POST /inventory/remove
- POST /inventory/use
- POST /inventory/transfer
- GET /world/me
- PUT /world/tiles
- PUT /world/tile
- GET /world/state
- POST /world/advance-season

## Findings

- Farm services refer to removed crop_type, nonexistent GROWTH_TIMES and advance_if_ready.
- Inventory output item_type differs from GameState item_code.
- get_db seeds and commits catalog data on every dependency use.
- Signup, token rotation and transfers contain multiple commits and partial failure paths.
- Currency and XP allow negative amounts; no balance checks in the database.
- World ownership is not unique; global state is publicly mutable.
- Farm coordinates are not unique and no progress accumulator exists.
- Player contains position and temporary account tokens; XP stores redundant values.
- Migration 003 adds a second world FK without removing the original; 004 destroys inventory data and adds a crop FK before seeding. Its downgrade drops reference tables before their dependents.
- Model refresh token hash lacks the migration unique constraint; several timestamp/default/index definitions differ.
- OAuth token audience verification is skipped if configuration is absent.
- Development email logger exposes raw verification and reset tokens.
- Old world tile JSON routes are not called by the current Godot client.
- Addendum sections 57-97 explicitly supersede the earlier forward-migration-only rule.
