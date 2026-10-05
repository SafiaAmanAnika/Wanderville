"""Per-crop harvest XP, multi-stack inventory rows and progression bookkeeping.

Additive only: no existing row loses a quantity, balance or entitlement.
"""

import sqlalchemy as sa
from alembic import op

revision = "0006_progression_and_stacks"
down_revision = "0005_shop_receipts"
branch_labels = None
depends_on = None

OLD_STACK_KEY = "uq_inventory_items_player_id"
NEW_STACK_KEY = "uq_inventory_items_player_stack"


def upgrade():
    op.add_column(
        "player_experience",
        sa.Column("inventory_base_capacity", sa.Integer(), nullable=False, server_default="30"),
    )
    with op.batch_alter_table("player_experience") as batch:
        batch.create_check_constraint("nonnegative_inventory_base", "inventory_base_capacity >= 0")
    # Plain ADD COLUMN works everywhere, so item_definitions never needs a
    # rebuild: SQLite cannot drop or rename a table other tables reference
    # while foreign keys are enforced. harvest_category stays NULL for items
    # that are never harvested (seeds, rods, pet items), so the client can tell
    # "no harvest XP" apart from "a common crop worth 5 XP". Allowed values
    # are enforced by the catalog and response schema, not a table constraint.
    op.add_column(
        "item_definitions",
        sa.Column("harvest_category", sa.String(16), nullable=True),
    )
    op.add_column(
        "item_definitions",
        sa.Column("harvest_xp", sa.Integer(), nullable=False, server_default="0"),
    )

    # One row per (item, stack_no) so a full stack no longer blocks a second
    # one; existing single-stack rows simply keep stack_no = 0. Nothing
    # references inventory_items, so the SQLite rebuild is safe.
    op.add_column(
        "inventory_items",
        sa.Column("stack_no", sa.Integer(), nullable=False, server_default="0"),
    )
    with op.batch_alter_table("inventory_items") as batch:
        batch.drop_constraint(OLD_STACK_KEY, type_="unique")
        batch.create_unique_constraint(
            NEW_STACK_KEY, ["player_id", "item_code", "location", "stack_no"]
        )
        batch.create_check_constraint("ck_inventory_items_stack_no", "stack_no >= 0")

    # Exactly-once level rewards and exactly-once first-harvest bonus.
    op.create_table(
        "player_level_rewards",
        sa.Column(
            "player_id",
            sa.Integer(),
            sa.ForeignKey("players.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        # Composite key: one row per crossed level, so a jump pays every
        # intermediate level exactly once.
        sa.Column("level", sa.Integer(), primary_key=True),
        sa.Column("aura", sa.Integer(), nullable=False, server_default="0"),
        sa.Column(
            "granted_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.CheckConstraint("level >= 1", name="reward_level"),
        sa.CheckConstraint("aura >= 0", name="reward_aura"),
    )
    op.create_table(
        "player_first_harvests",
        sa.Column(
            "player_id",
            sa.Integer(),
            sa.ForeignKey("players.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column(
            "item_code",
            sa.String(32),
            sa.ForeignKey("item_definitions.item_code"),
            primary_key=True,
        ),
        sa.Column(
            "harvested_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
    )

    # Preserve the six old advertised partition allowances as one durable base
    # for pre-existing accounts. Future accounts receive the configured single
    # base. No inventory, balance, lifetime XP or old receipt is overwritten.
    from app.core.config import settings

    connection = op.get_bind()
    levels = (0, 80, 180, 320, 500, 750, 1050, 1400, 1800, 2100)
    for player_id, total_xp, old_level in connection.execute(
        sa.text("SELECT player_id, total_xp, level FROM player_experience")
    ).all():
        level = sum(total_xp >= threshold for threshold in levels)
        occupied = connection.scalar(sa.text(
            "SELECT count(*) FROM inventory_items WHERE player_id=:player_id"
        ), {"player_id": player_id})
        connection.execute(sa.text(
            "UPDATE player_experience SET inventory_base_capacity=:capacity, level=:level "
            "WHERE player_id=:player_id"
        ), {"player_id": player_id, "capacity": max(settings.inventory_partition_slots * 6, occupied),
            "level": level})
        # Old issuance cannot be reconstructed reliably: mark historical levels
        # as handled, paying no retrospective Aura. Only future crossings pay.
        for reward_level in (2, 10):
            if reward_level <= max(level, old_level):
                connection.execute(sa.text(
                    "INSERT INTO player_level_rewards (player_id,level,aura) VALUES (:player_id,:level,0)"
                ), {"player_id": player_id, "level": reward_level})


def downgrade():
    op.drop_table("player_first_harvests")
    op.drop_table("player_level_rewards")
    with op.batch_alter_table("inventory_items") as batch:
        batch.drop_constraint("ck_inventory_items_stack_no", type_="check")
        batch.drop_constraint(NEW_STACK_KEY, type_="unique")
        batch.create_unique_constraint(
            OLD_STACK_KEY, ["player_id", "item_code", "location"]
        )
    op.drop_column("inventory_items", "stack_no")
    op.drop_column("item_definitions", "harvest_xp")
    op.drop_column("item_definitions", "harvest_category")
    with op.batch_alter_table("player_experience") as batch:
        batch.drop_constraint(op.f("ck_player_experience_nonnegative_inventory_base"), type_="check")
        batch.drop_column("inventory_base_capacity")
