"""player shops"""

import sqlalchemy as sa
from alembic import op

revision = "0009_player_shops"
down_revision = "0008_proximity_social"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "player_shops",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "owner_id",
            sa.Integer(),
            sa.ForeignKey("players.id", ondelete="CASCADE"),
            nullable=False,
            unique=True,
        ),
        sa.Column("option_id", sa.String(32), nullable=False),
        sa.Column("side", sa.String(5), nullable=False),
        sa.Column("name", sa.String(64), nullable=False),
        sa.Column("created_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("side IN ('left','right')", name="side"),
    )
    op.create_table(
        "shop_listings",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("shop_id", sa.Integer(), sa.ForeignKey("player_shops.id", ondelete="CASCADE"), nullable=False),
        sa.Column("item_code", sa.String(64), sa.ForeignKey("item_definitions.item_code"), nullable=False),
        sa.Column("quantity", sa.Integer(), nullable=False),
        sa.Column("price", sa.Integer(), nullable=False),
        sa.CheckConstraint("quantity >= 0", name="qty"),
        sa.CheckConstraint("price > 0", name="price"),
    )
    op.create_index("player_shop_listing_unique", "shop_listings", ["shop_id", "item_code"], unique=True)
    op.create_table(
        "player_shop_sales",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("shop_id", sa.Integer(), sa.ForeignKey("player_shops.id", ondelete="CASCADE"), nullable=False),
        sa.Column("buyer_id", sa.Integer(), sa.ForeignKey("players.id"), nullable=False),
        sa.Column("item_code", sa.String(64), nullable=False),
        sa.Column("quantity", sa.Integer(), nullable=False),
        sa.Column("price", sa.Integer(), nullable=False),
        sa.Column("sold_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
    )


def downgrade():
    op.drop_table("player_shop_sales")
    op.drop_index("player_shop_listing_unique", table_name="shop_listings")
    op.drop_table("shop_listings")
    op.drop_table("player_shops")