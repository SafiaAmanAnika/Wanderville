"""add_world_table

Revision ID: 002_add_world_table
Revises: 001_initial_schema
Create Date: 2026-05-17 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '002_add_world_table'
down_revision: Union[str, None] = '001_initial_schema'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'worlds',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('owner_id', sa.Integer(), nullable=False),
        sa.Column('name', sa.String(length=64), nullable=False, server_default=sa.text("'My World'")),
        sa.Column('tiles', sa.JSON(), nullable=False, server_default=sa.text("'{}'")),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['owner_id'], ['players.id']),
    )
    op.create_index(op.f('ix_worlds_owner_id'), 'worlds', ['owner_id'], unique=False)


def downgrade() -> None:
    op.drop_index(op.f('ix_worlds_owner_id'), table_name='worlds')
    op.drop_table('worlds')
