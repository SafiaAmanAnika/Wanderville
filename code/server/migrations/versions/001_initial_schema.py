"""initial_schema

Revision ID: 001_initial_schema
Revises: 
Create Date: 2026-05-17 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '001_initial_schema'
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'players',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('username', sa.String(length=32), nullable=False),
        sa.Column('hashed_password', sa.String(length=255), nullable=False),
        sa.Column('display_name', sa.String(length=64), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column('position_x', sa.Integer(), nullable=False, server_default=sa.text('0')),
        sa.Column('position_y', sa.Integer(), nullable=False, server_default=sa.text('0')),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('username'),
    )
    op.create_index(op.f('ix_players_username'), 'players', ['username'], unique=True)


def downgrade() -> None:
    op.drop_index(op.f('ix_players_username'), table_name='players')
    op.drop_table('players')
