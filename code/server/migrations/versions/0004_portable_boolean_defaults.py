"""Normalize gameplay Boolean defaults on existing PostgreSQL deployments.

Historical revisions remain unchanged. env.py renders their numeric Boolean
literals portably for fresh PostgreSQL installs; this revision explicitly aligns
existing PostgreSQL defaults with ORM metadata. SQLite keeps its equivalent 0/1.
"""

from alembic import op
import sqlalchemy as sa

revision = "0004_boolean_defaults"
down_revision = "0003_presence"
branch_labels = None
depends_on = None


def upgrade():
    if op.get_bind().dialect.name != "postgresql":
        return
    defaults = {
        "fishing_spots": ("freezes_in_winter",),
        "fishing_sessions": ("resolved",),
        "ground_drops": ("claimed",),
        "gifts": ("claimed",),
        "goal_progress": ("rewarded",),
        "item_rules": ("pet_food", "pet_accessory", "fishing_rod"),
        "notifications": ("is_read", "dismissed"),
        "player_profiles": ("fullscreen",),
        "social_invites": ("accepted",),
    }
    for table, columns in defaults.items():
        for column in columns:
            op.alter_column(
                table, column, existing_type=sa.Boolean(), server_default=sa.false(),
            )


def downgrade():
    # Portable defaults are semantically identical; never restore invalid PG DDL.
    pass
