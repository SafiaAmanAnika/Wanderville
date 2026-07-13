"""add auth upgrade — email, refresh tokens, security fields

Revision ID: 005_add_auth_upgrade
Revises: 004_add_persistence_layer
Create Date: 2026-07-13 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '005_add_auth_upgrade'
down_revision: Union[str, None] = '004_add_persistence_layer'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # --- Players table: add new columns (all nullable for backward compat) ---
    op.add_column('players', sa.Column('email', sa.String(255), nullable=True))
    op.add_column('players', sa.Column('email_verified', sa.Boolean(), server_default='false', nullable=False))
    op.add_column('players', sa.Column('email_verification_token', sa.String(255), nullable=True))
    op.add_column('players', sa.Column('email_verification_expires', sa.DateTime(timezone=True), nullable=True))
    op.add_column('players', sa.Column('password_reset_token', sa.String(255), nullable=True))
    op.add_column('players', sa.Column('password_reset_expires', sa.DateTime(timezone=True), nullable=True))
    op.add_column('players', sa.Column('oauth_provider', sa.String(32), nullable=True))
    op.add_column('players', sa.Column('oauth_provider_id', sa.String(255), nullable=True))
    op.add_column('players', sa.Column('avatar_url', sa.String(512), nullable=True))
    op.add_column('players', sa.Column('failed_login_attempts', sa.Integer(), server_default='0', nullable=False))
    op.add_column('players', sa.Column('locked_until', sa.DateTime(timezone=True), nullable=True))
    op.add_column('players', sa.Column('last_login_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('players', sa.Column('last_login_ip', sa.String(45), nullable=True))

    # Make hashed_password nullable (OAuth users won't have a password)
    op.alter_column('players', 'hashed_password', nullable=True)

    # Indexes for new columns
    op.create_index('ix_players_email', 'players', ['email'], unique=True)

    # --- Refresh tokens table ---
    op.create_table(
        'refresh_tokens',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('token_hash', sa.String(64), nullable=False),
        sa.Column('player_id', sa.Integer(), nullable=False),
        sa.Column('device_info', sa.String(255), nullable=True),
        sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('revoked', sa.Boolean(), server_default='false', nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(['player_id'], ['players.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_refresh_tokens_token_hash', 'refresh_tokens', ['token_hash'], unique=True)
    op.create_index('ix_refresh_tokens_player_id', 'refresh_tokens', ['player_id'])


def downgrade() -> None:
    op.drop_table('refresh_tokens')

    op.drop_index('ix_players_email', table_name='players')
    op.drop_column('players', 'last_login_ip')
    op.drop_column('players', 'last_login_at')
    op.drop_column('players', 'locked_until')
    op.drop_column('players', 'failed_login_attempts')
    op.drop_column('players', 'avatar_url')
    op.drop_column('players', 'oauth_provider_id')
    op.drop_column('players', 'oauth_provider')
    op.drop_column('players', 'password_reset_expires')
    op.drop_column('players', 'password_reset_token')
    op.drop_column('players', 'email_verification_expires')
    op.drop_column('players', 'email_verification_token')
    op.drop_column('players', 'email_verified')
    op.drop_column('players', 'email')

    op.alter_column('players', 'hashed_password', nullable=False)
