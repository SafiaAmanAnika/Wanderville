"""Proximity text receipts, preferences, wishlist and gift allocations.

Only additive ALTERs on existing SQLite tables: do not rebuild cascade parents.
"""

from alembic import op
import sqlalchemy as sa

revision = "0008_proximity_social"
down_revision = "0007_farm_visiting"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column(
        "player_presence",
        sa.Column("room_epoch", sa.Integer(), nullable=False, server_default="0"),
    )
    op.add_column(
        "nearby_messages",
        sa.Column("room", sa.String(64), nullable=False, server_default="__legacy__"),
    )
    op.add_column(
        "nearby_messages",
        sa.Column("sender_epoch", sa.Integer(), nullable=False, server_default="0"),
    )
    op.add_column(
        "nearby_messages", sa.Column("created_at", sa.DateTime(timezone=True))
    )
    op.add_column(
        "nearby_message_recipients",
        sa.Column("room_epoch", sa.Integer(), nullable=False, server_default="0"),
    )
    op.create_table(
        "social_preferences",
        sa.Column(
            "player_id",
            sa.Integer(),
            sa.ForeignKey("players.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column(
            "voice_privacy", sa.String(16), nullable=False, server_default="friends"
        ),
        sa.Column(
            "wishlist_visibility",
            sa.String(16),
            nullable=False,
            server_default="friends",
        ),
        sa.Column(
            "proximity_prompts", sa.Boolean(), nullable=False, server_default=sa.true()
        ),
        sa.CheckConstraint(
            "voice_privacy IN ('off','friends','nearby')", name="voice_privacy"
        ),
        sa.CheckConstraint(
            "wishlist_visibility IN ('private','friends')", name="wishlist_visibility"
        ),
    )
    op.create_table(
        "wishlist_entries",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "player_id",
            sa.Integer(),
            sa.ForeignKey("players.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "item_code",
            sa.String(32),
            sa.ForeignKey("item_definitions.item_code"),
            nullable=False,
        ),
        sa.Column("quantity", sa.Integer(), nullable=False),
        sa.Column("priority", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("version", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.UniqueConstraint("player_id", "item_code"),
        sa.CheckConstraint(
            "quantity > 0 AND quantity <= 99 AND priority >= 0 AND priority <= 10 AND version > 0",
            name="values",
        ),
    )
    op.create_index(
        "ix_wishlist_owner_active", "wishlist_entries", ["player_id", "active"]
    )
    op.create_table(
        "gift_wishlist_allocations",
        sa.Column(
            "gift_id",
            sa.Integer(),
            sa.ForeignKey("gifts.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column(
            "entry_id",
            sa.Integer(),
            sa.ForeignKey("wishlist_entries.id"),
            nullable=False,
        ),
        sa.Column("expected_version", sa.Integer(), nullable=False),
    )
    op.create_index(
        "ix_gift_wishlist_allocations_entry_id",
        "gift_wishlist_allocations",
        ["entry_id"],
    )
    op.create_table(
        "nearby_chat_receipts",
        sa.Column(
            "sender_id",
            sa.Integer(),
            sa.ForeignKey("players.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("request_id", sa.String(64), primary_key=True),
        sa.Column("body_hash", sa.String(64), nullable=False),
        sa.Column("message_id", sa.Integer(), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index(
        "ix_nearby_chat_receipts_expires_at", "nearby_chat_receipts", ["expires_at"]
    )
    op.create_table(
        "social_revisions",
        sa.Column(
            "player_id",
            sa.Integer(),
            sa.ForeignKey("players.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("revision", sa.Integer(), nullable=False, server_default="1"),
    )


def downgrade():
    for table in (
        "social_revisions",
        "nearby_chat_receipts",
        "gift_wishlist_allocations",
        "wishlist_entries",
        "social_preferences",
    ):
        op.drop_table(table)
    op.drop_column("nearby_message_recipients", "room_epoch")
    for column in ("created_at", "sender_epoch", "room"):
        op.drop_column("nearby_messages", column)
    op.drop_column("player_presence", "room_epoch")
