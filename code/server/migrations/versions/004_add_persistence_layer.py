"""add persistence layer

Revision ID: 004_add_persistence_layer
Revises: fe33f4e10006
Create Date: 2026-06-30 22:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '004_add_persistence_layer'
down_revision: Union[str, None] = 'fe33f4e10006'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1. Item Definitions (master catalog)
    op.create_table(
        'item_definitions',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('item_code', sa.String(32), nullable=False),
        sa.Column('name', sa.String(64), nullable=False),
        sa.Column('category', sa.String(32), nullable=False),
        sa.Column('max_stack', sa.Integer(), server_default='99', nullable=False),
        sa.Column('sell_value', sa.Integer(), server_default='0', nullable=False),
        sa.Column('buy_value', sa.Integer(), nullable=True),
        sa.Column('growth_time_seconds', sa.Integer(), nullable=True),
        sa.Column('season', sa.String(16), server_default='all', nullable=False),
        sa.Column('xp_reward', sa.Integer(), server_default='0', nullable=False),
        sa.Column('rarity', sa.String(16), server_default='common', nullable=False),
        sa.Column('tradable', sa.Boolean(), server_default='true', nullable=False),
        sa.Column('giftable', sa.Boolean(), server_default='true', nullable=False),
        sa.Column('usable', sa.Boolean(), server_default='false', nullable=False),
        sa.Column('placeable', sa.Boolean(), server_default='false', nullable=False),
        sa.Column('icon_path', sa.String(255), nullable=True),
        sa.Column('description', sa.String(512), nullable=True),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('item_code')
    )
    op.create_index('ix_item_def_category', 'item_definitions', ['category'])
    op.create_index('ix_item_def_season', 'item_definitions', ['season'])
    op.create_index(op.f('ix_item_definitions_item_code'), 'item_definitions', ['item_code'], unique=True)

    # 2. Player Economy
    op.create_table(
        'player_economy',
        sa.Column('player_id', sa.Integer(), nullable=False),
        sa.Column('taka_balance', sa.Integer(), server_default='0', nullable=False),
        sa.Column('coin_balance', sa.Integer(), server_default='0', nullable=False),
        sa.Column('total_earned', sa.Integer(), server_default='0', nullable=False),
        sa.Column('total_spent', sa.Integer(), server_default='0', nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(['player_id'], ['players.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('player_id')
    )

    # 3. Player Experience
    op.create_table(
        'player_experience',
        sa.Column('player_id', sa.Integer(), nullable=False),
        sa.Column('current_xp', sa.Integer(), server_default='0', nullable=False),
        sa.Column('total_xp', sa.Integer(), server_default='0', nullable=False),
        sa.Column('level', sa.Integer(), server_default='1', nullable=False),
        sa.Column('xp_to_next_level', sa.Integer(), server_default='100', nullable=False),
        sa.Column('title', sa.String(64), nullable=True),
        sa.ForeignKeyConstraint(['player_id'], ['players.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('player_id')
    )

    # 4. World State (global season/time)
    op.create_table(
        'world_state',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('current_season', sa.String(16), server_default='summer', nullable=False),
        sa.Column('season_start_time', sa.DateTime(timezone=True), nullable=True),
        sa.Column('season_duration_minutes', sa.Integer(), server_default='10080', nullable=False),
        sa.Column('day_night_cycle_minutes', sa.Integer(), server_default='40', nullable=False),
        sa.Column('current_time_of_day', sa.Float(), server_default='0.0', nullable=False),
        sa.Column('is_raining', sa.Boolean(), server_default='false', nullable=False),
        sa.Column('last_updated', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
        sa.PrimaryKeyConstraint('id')
    )

    # 5. Migrate inventory_items (drop old, create new with FK)
    op.drop_table('inventory_items')
    op.create_table(
        'inventory_items',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('player_id', sa.Integer(), nullable=False),
        sa.Column('item_code', sa.String(32), nullable=False),
        sa.Column('quantity', sa.Integer(), server_default='1', nullable=False),
        sa.Column('slot_index', sa.Integer(), nullable=True),
        sa.Column('location', sa.String(16), server_default='inventory', nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(['item_code'], ['item_definitions.item_code']),
        sa.ForeignKeyConstraint(['player_id'], ['players.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_inventory_items_player_id'), 'inventory_items', ['player_id'])
    op.create_index('ix_inventory_player_location', 'inventory_items', ['player_id', 'location'])
    op.create_unique_constraint('uix_player_item_location', 'inventory_items', ['player_id', 'item_code', 'location'])

    # 6. Migrate farm_plots: crop_type → item_code with FK
    op.add_column('farm_plots', sa.Column('item_code', sa.String(32), nullable=True))
    op.execute("UPDATE farm_plots SET item_code = crop_type WHERE crop_type IS NOT NULL")
    op.drop_column('farm_plots', 'crop_type')
    op.create_foreign_key('fk_farm_plots_item_code', 'farm_plots', 'item_definitions', ['item_code'], ['item_code'])


def downgrade() -> None:
    op.drop_table('world_state')
    op.drop_table('player_experience')
    op.drop_table('player_economy')
    op.drop_table('item_definitions')
    op.drop_table('inventory_items')
    op.drop_constraint('fk_farm_plots_item_code', 'farm_plots', type_='foreignkey')
    op.drop_column('farm_plots', 'item_code')
    op.add_column('farm_plots', sa.Column('crop_type', sa.String(32), nullable=True))