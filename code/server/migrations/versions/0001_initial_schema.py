"""initial clean schema

Revision ID: 0001_initial_schema
Revises:
Create Date: 2026-09-30 08:20:41.605740

"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "0001_initial_schema"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Reviewed baseline: portable boolean/time defaults, named constraints, dependency order.
    op.create_table(
        "item_definitions",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("item_code", sa.String(length=32), nullable=False),
        sa.Column("name", sa.String(length=64), nullable=False),
        sa.Column("category", sa.String(length=32), nullable=False),
        sa.Column("max_stack", sa.Integer(), server_default="99", nullable=False),
        sa.Column("sell_value", sa.Integer(), server_default="0", nullable=False),
        sa.Column("buy_value", sa.Integer(), nullable=True),
        sa.Column("growth_time_seconds", sa.Integer(), nullable=True),
        sa.Column("season", sa.String(length=16), server_default="all", nullable=False),
        sa.Column("xp_reward", sa.Integer(), server_default="0", nullable=False),
        sa.Column(
            "rarity", sa.String(length=16), server_default="common", nullable=False
        ),
        sa.Column("tradable", sa.Boolean(), server_default=sa.true(), nullable=False),
        sa.Column("giftable", sa.Boolean(), server_default=sa.true(), nullable=False),
        sa.Column("usable", sa.Boolean(), server_default=sa.false(), nullable=False),
        sa.Column("placeable", sa.Boolean(), server_default=sa.false(), nullable=False),
        sa.Column("icon_path", sa.String(length=255), nullable=True),
        sa.Column("description", sa.String(length=512), nullable=True),
        sa.CheckConstraint(
            "season IN ('all', 'spring', 'summer', 'autumn', 'winter')",
            name=op.f("ck_item_definitions_season"),
        ),
        sa.CheckConstraint(
            "buy_value IS NULL OR buy_value >= 0",
            name=op.f("ck_item_definitions_nonnegative_buy"),
        ),
        sa.CheckConstraint(
            "growth_time_seconds IS NULL OR growth_time_seconds > 0",
            name=op.f("ck_item_definitions_positive_growth"),
        ),
        sa.CheckConstraint(
            "max_stack > 0", name=op.f("ck_item_definitions_positive_stack")
        ),
        sa.CheckConstraint(
            "sell_value >= 0", name=op.f("ck_item_definitions_nonnegative_sell")
        ),
        sa.CheckConstraint(
            "xp_reward >= 0", name=op.f("ck_item_definitions_nonnegative_xp")
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_item_definitions")),
        sa.UniqueConstraint("item_code", name=op.f("uq_item_definitions_item_code")),
    )
    op.create_index(
        op.f("ix_item_definitions_category"),
        "item_definitions",
        ["category"],
        unique=False,
    )
    op.create_index(
        op.f("ix_item_definitions_season"), "item_definitions", ["season"], unique=False
    )
    op.create_table(
        "players",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("username", sa.String(length=32), nullable=False),
        sa.Column("email", sa.String(length=255), nullable=True),
        sa.Column("hashed_password", sa.String(length=255), nullable=True),
        sa.Column("display_name", sa.String(length=64), nullable=False),
        sa.Column("is_active", sa.Boolean(), server_default=sa.true(), nullable=False),
        sa.Column(
            "email_verified", sa.Boolean(), server_default=sa.false(), nullable=False
        ),
        sa.Column("oauth_provider", sa.String(length=32), nullable=True),
        sa.Column("oauth_provider_id", sa.String(length=255), nullable=True),
        sa.Column("avatar_url", sa.String(length=512), nullable=True),
        sa.Column(
            "failed_login_attempts", sa.Integer(), server_default="0", nullable=False
        ),
        sa.Column("locked_until", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_login_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_login_ip", sa.String(length=45), nullable=True),
        sa.Column("token_version", sa.Integer(), server_default="0", nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.CheckConstraint(
            "failed_login_attempts >= 0", name=op.f("ck_players_nonnegative_attempts")
        ),
        sa.CheckConstraint(
            "token_version >= 0", name=op.f("ck_players_nonnegative_token_version")
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_players")),
        sa.UniqueConstraint("email", name=op.f("uq_players_email")),
        sa.UniqueConstraint(
            "oauth_provider",
            "oauth_provider_id",
            name=op.f("uq_players_oauth_provider"),
        ),
        sa.UniqueConstraint("username", name=op.f("uq_players_username")),
    )
    op.create_table(
        "world_state",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column(
            "current_season",
            sa.String(length=16),
            server_default="summer",
            nullable=False,
        ),
        sa.Column(
            "season_started_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "season_duration_minutes",
            sa.Integer(),
            server_default="10080",
            nullable=False,
        ),
        sa.Column(
            "weather", sa.String(length=16), server_default="clear", nullable=False
        ),
        sa.Column(
            "day_cycle_anchor_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "day_night_cycle_minutes", sa.Integer(), server_default="40", nullable=False
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.CheckConstraint(
            "current_season IN ('spring', 'summer', 'autumn', 'winter')",
            name=op.f("ck_world_state_season"),
        ),
        sa.CheckConstraint(
            "weather IN ('clear', 'rain', 'snow')", name=op.f("ck_world_state_weather")
        ),
        sa.CheckConstraint(
            "day_night_cycle_minutes > 0",
            name=op.f("ck_world_state_positive_day_duration"),
        ),
        sa.CheckConstraint("id = 1", name=op.f("ck_world_state_singleton")),
        sa.CheckConstraint(
            "season_duration_minutes > 0",
            name=op.f("ck_world_state_positive_season_duration"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_world_state")),
    )
    op.create_table(
        "account_tokens",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("player_id", sa.Integer(), nullable=False),
        sa.Column("token_hash", sa.String(length=64), nullable=False),
        sa.Column("token_type", sa.String(length=32), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("used_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.CheckConstraint(
            "token_type IN ('email_verification', 'password_reset')",
            name=op.f("ck_account_tokens_token_type"),
        ),
        sa.ForeignKeyConstraint(
            ["player_id"],
            ["players.id"],
            name=op.f("fk_account_tokens_player_id_players"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_account_tokens")),
        sa.UniqueConstraint("token_hash", name=op.f("uq_account_tokens_token_hash")),
    )
    op.create_index(
        op.f("ix_account_tokens_player_id"),
        "account_tokens",
        ["player_id"],
        unique=False,
    )
    op.create_table(
        "economy_transactions",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("player_id", sa.Integer(), nullable=False),
        sa.Column("amount", sa.BigInteger(), nullable=False),
        sa.Column("transaction_type", sa.String(length=16), nullable=False),
        sa.Column("reason", sa.String(length=255), nullable=False),
        sa.Column("reference_type", sa.String(length=32), nullable=True),
        sa.Column("reference_id", sa.String(length=64), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.CheckConstraint(
            "(transaction_type = 'earn' AND amount > 0) OR (transaction_type = 'spend' AND amount < 0)",
            name=op.f("ck_economy_transactions_signed_amount"),
        ),
        sa.ForeignKeyConstraint(
            ["player_id"],
            ["players.id"],
            name=op.f("fk_economy_transactions_player_id_players"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_economy_transactions")),
    )
    op.create_index(
        op.f("ix_economy_transactions_created_at"),
        "economy_transactions",
        ["created_at"],
        unique=False,
    )
    op.create_index(
        op.f("ix_economy_transactions_player_id"),
        "economy_transactions",
        ["player_id"],
        unique=False,
    )
    op.create_table(
        "inventory_items",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("player_id", sa.Integer(), nullable=False),
        sa.Column("item_code", sa.String(length=32), nullable=False),
        sa.Column("quantity", sa.Integer(), nullable=False),
        sa.Column("slot_index", sa.Integer(), nullable=True),
        sa.Column(
            "location", sa.String(length=16), server_default="inventory", nullable=False
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.CheckConstraint(
            "location = 'inventory'", name=op.f("ck_inventory_items_supported_location")
        ),
        sa.CheckConstraint(
            "quantity > 0", name=op.f("ck_inventory_items_positive_quantity")
        ),
        sa.CheckConstraint(
            "slot_index IS NULL OR slot_index >= 0",
            name=op.f("ck_inventory_items_nonnegative_slot"),
        ),
        sa.ForeignKeyConstraint(
            ["item_code"],
            ["item_definitions.item_code"],
            name=op.f("fk_inventory_items_item_code_item_definitions"),
        ),
        sa.ForeignKeyConstraint(
            ["player_id"],
            ["players.id"],
            name=op.f("fk_inventory_items_player_id_players"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_inventory_items")),
        sa.UniqueConstraint(
            "player_id",
            "item_code",
            "location",
            name=op.f("uq_inventory_items_player_id"),
        ),
    )
    op.create_index(
        op.f("ix_inventory_items_item_code"),
        "inventory_items",
        ["item_code"],
        unique=False,
    )
    op.create_index(
        op.f("ix_inventory_items_player_id"),
        "inventory_items",
        ["player_id"],
        unique=False,
    )
    op.create_index(
        "ix_inventory_player_location",
        "inventory_items",
        ["player_id", "location"],
        unique=False,
    )
    op.create_table(
        "player_economy",
        sa.Column("player_id", sa.Integer(), nullable=False),
        sa.Column("aura_balance", sa.BigInteger(), server_default="0", nullable=False),
        sa.Column("total_earned", sa.BigInteger(), server_default="0", nullable=False),
        sa.Column("total_spent", sa.BigInteger(), server_default="0", nullable=False),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.CheckConstraint(
            "aura_balance >= 0", name=op.f("ck_player_economy_nonnegative_aura_balance")
        ),
        sa.CheckConstraint(
            "total_earned >= 0", name=op.f("ck_player_economy_nonnegative_total_earned")
        ),
        sa.CheckConstraint(
            "total_spent >= 0", name=op.f("ck_player_economy_nonnegative_total_spent")
        ),
        sa.ForeignKeyConstraint(
            ["player_id"],
            ["players.id"],
            name=op.f("fk_player_economy_player_id_players"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("player_id", name=op.f("pk_player_economy")),
    )
    op.create_table(
        "player_experience",
        sa.Column("player_id", sa.Integer(), nullable=False),
        sa.Column("total_xp", sa.BigInteger(), server_default="0", nullable=False),
        sa.Column("level", sa.Integer(), server_default="1", nullable=False),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.CheckConstraint(
            "level >= 1", name=op.f("ck_player_experience_positive_level")
        ),
        sa.CheckConstraint(
            "total_xp >= 0", name=op.f("ck_player_experience_nonnegative_xp")
        ),
        sa.ForeignKeyConstraint(
            ["player_id"],
            ["players.id"],
            name=op.f("fk_player_experience_player_id_players"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("player_id", name=op.f("pk_player_experience")),
    )
    op.create_table(
        "player_worlds",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("owner_id", sa.Integer(), nullable=False),
        sa.Column(
            "name", sa.String(length=64), server_default="My World", nullable=False
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["owner_id"],
            ["players.id"],
            name=op.f("fk_player_worlds_owner_id_players"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_player_worlds")),
        sa.UniqueConstraint("owner_id", name=op.f("uq_player_worlds_owner_id")),
    )
    op.create_table(
        "refresh_tokens",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("player_id", sa.Integer(), nullable=False),
        sa.Column("token_hash", sa.String(length=64), nullable=False),
        sa.Column("device_info", sa.String(length=255), nullable=True),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["player_id"],
            ["players.id"],
            name=op.f("fk_refresh_tokens_player_id_players"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_refresh_tokens")),
        sa.UniqueConstraint("token_hash", name=op.f("uq_refresh_tokens_token_hash")),
    )
    op.create_index(
        op.f("ix_refresh_tokens_player_id"),
        "refresh_tokens",
        ["player_id"],
        unique=False,
    )
    op.create_table(
        "farm_tiles",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("world_id", sa.Integer(), nullable=False),
        sa.Column("x", sa.Integer(), nullable=False),
        sa.Column("y", sa.Integer(), nullable=False),
        sa.Column("is_tilled", sa.Boolean(), server_default=sa.true(), nullable=False),
        sa.Column("crop_item_code", sa.String(length=32), nullable=True),
        sa.Column("planted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "growth_progress_seconds", sa.Float(), server_default="0", nullable=False
        ),
        sa.Column("growth_stage", sa.Integer(), server_default="0", nullable=False),
        sa.Column("last_growth_update_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "is_watered", sa.Boolean(), server_default=sa.false(), nullable=False
        ),
        sa.Column("watered_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.CheckConstraint(
            "(crop_item_code IS NOT NULL AND is_tilled AND planted_at IS NOT NULL AND last_growth_update_at IS NOT NULL) OR (crop_item_code IS NULL AND planted_at IS NULL AND growth_progress_seconds = 0 AND growth_stage = 0 AND NOT is_watered AND watered_at IS NULL AND last_growth_update_at IS NULL)",
            name=op.f("ck_farm_tiles_crop_state"),
        ),
        sa.CheckConstraint(
            "NOT is_watered OR watered_at IS NOT NULL",
            name=op.f("ck_farm_tiles_water_timestamp"),
        ),
        sa.CheckConstraint(
            "growth_progress_seconds >= 0",
            name=op.f("ck_farm_tiles_nonnegative_progress"),
        ),
        sa.CheckConstraint(
            "growth_stage BETWEEN 0 AND 3", name=op.f("ck_farm_tiles_growth_stage")
        ),
        sa.CheckConstraint(
            "x >= 0 AND y >= 0", name=op.f("ck_farm_tiles_nonnegative_coordinates")
        ),
        sa.ForeignKeyConstraint(
            ["crop_item_code"],
            ["item_definitions.item_code"],
            name=op.f("fk_farm_tiles_crop_item_code_item_definitions"),
        ),
        sa.ForeignKeyConstraint(
            ["world_id"],
            ["player_worlds.id"],
            name=op.f("fk_farm_tiles_world_id_player_worlds"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_farm_tiles")),
        sa.UniqueConstraint("world_id", "x", "y", name=op.f("uq_farm_tiles_world_id")),
    )
    op.create_index(
        op.f("ix_farm_tiles_crop_item_code"),
        "farm_tiles",
        ["crop_item_code"],
        unique=False,
    )
    op.create_index(
        op.f("ix_farm_tiles_world_id"), "farm_tiles", ["world_id"], unique=False
    )


def downgrade() -> None:
    # Reviewed baseline: portable boolean/time defaults, named constraints, dependency order.
    op.drop_index(op.f("ix_farm_tiles_world_id"), table_name="farm_tiles")
    op.drop_index(op.f("ix_farm_tiles_crop_item_code"), table_name="farm_tiles")
    op.drop_table("farm_tiles")
    op.drop_index(op.f("ix_refresh_tokens_player_id"), table_name="refresh_tokens")
    op.drop_table("refresh_tokens")
    op.drop_table("player_worlds")
    op.drop_table("player_experience")
    op.drop_table("player_economy")
    op.drop_index("ix_inventory_player_location", table_name="inventory_items")
    op.drop_index(op.f("ix_inventory_items_player_id"), table_name="inventory_items")
    op.drop_index(op.f("ix_inventory_items_item_code"), table_name="inventory_items")
    op.drop_table("inventory_items")
    op.drop_index(
        op.f("ix_economy_transactions_player_id"), table_name="economy_transactions"
    )
    op.drop_index(
        op.f("ix_economy_transactions_created_at"), table_name="economy_transactions"
    )
    op.drop_table("economy_transactions")
    op.drop_index(op.f("ix_account_tokens_player_id"), table_name="account_tokens")
    op.drop_table("account_tokens")
    op.drop_table("world_state")
    op.drop_table("players")
    op.drop_index(op.f("ix_item_definitions_season"), table_name="item_definitions")
    op.drop_index(op.f("ix_item_definitions_category"), table_name="item_definitions")
    op.drop_table("item_definitions")
