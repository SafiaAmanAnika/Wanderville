"""per-player trees: map trees cut, trees grown after a season is cleared"""

import sqlalchemy as sa
from alembic import op

revision = "0011_trees"
down_revision = "0010_schema_drift"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "player_cut_trees",
        sa.Column("player_id", sa.Integer(), sa.ForeignKey("players.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("tree_id", sa.String(64), primary_key=True),
        sa.Column("cut_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_table(
        "player_spawned_trees",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("player_id", sa.Integer(), sa.ForeignKey("players.id", ondelete="CASCADE"), nullable=False),
        sa.Column("season", sa.String(8), nullable=False),
        sa.Column("scene", sa.String(128), nullable=False),
        sa.Column("x", sa.Float(), nullable=False),
        sa.Column("y", sa.Float(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("season IN ('summer','autumn','winter','spring')", name="season"),
    )
    op.create_index("ix_player_spawned_trees_player_id", "player_spawned_trees", ["player_id"])


def downgrade():
    op.drop_index("ix_player_spawned_trees_player_id", "player_spawned_trees")
    op.drop_table("player_spawned_trees")
    op.drop_table("player_cut_trees")
