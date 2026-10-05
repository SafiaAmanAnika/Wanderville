"""Track one-time seed grants and idempotent sales without touching player data."""
from alembic import op
import sqlalchemy as sa

revision = "0005_shop_receipts"
down_revision = "0004_boolean_defaults"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "starter_grants",
        sa.Column("player_id", sa.Integer(), sa.ForeignKey("players.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("grant_code", sa.String(32), primary_key=True),
        sa.Column("claimed_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )
    op.create_table(
        "shop_sales",
        sa.Column("player_id", sa.Integer(), sa.ForeignKey("players.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("request_id", sa.String(64), primary_key=True),
        sa.Column("item_code", sa.String(32), sa.ForeignKey("item_definitions.item_code"), nullable=False),
        sa.Column("quantity", sa.Integer(), nullable=False),
        sa.Column("unit_price", sa.Integer(), nullable=False),
        sa.CheckConstraint("quantity > 0 AND unit_price > 0", name="sale_values"),
    )


def downgrade():
    op.drop_table("shop_sales")
    op.drop_table("starter_grants")
