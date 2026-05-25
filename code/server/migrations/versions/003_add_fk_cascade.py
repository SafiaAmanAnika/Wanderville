"""add fk cascade on worlds.owner_id

Revision ID: 003_add_fk_cascade
Revises: 002_add_world_table
Create Date: 2026-05-17 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '003_add_fk_cascade'
down_revision: Union[str, None] = '002_add_world_table'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # SQLite requires recreating the table to change FK constraints.
    # Use batch mode which handles the recreate automatically.
    with op.batch_alter_table('worlds', schema=None) as batch_op:
        batch_op.create_foreign_key(
            'fk_worlds_owner_id_players',
            'players',
            ['owner_id'],
            ['id'],
            ondelete='CASCADE'
        )


def downgrade() -> None:
    with op.batch_alter_table('worlds', schema=None) as batch_op:
        batch_op.drop_constraint('fk_worlds_owner_id_players', type_='foreignkey')
        batch_op.create_foreign_key(
            'fk_worlds_owner_id_players',
            'players',
            ['owner_id'],
            ['id']
        )
