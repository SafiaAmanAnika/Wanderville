"""align listing item codes with the catalog"""

import sqlalchemy as sa
from alembic import op

revision = "0010_schema_drift"
down_revision = "0009_player_shops"
branch_labels = None
depends_on = None


def upgrade():
    # The column references item_definitions.item_code, so it can never hold more than 32.
    with op.batch_alter_table("shop_listings") as batch:
        batch.alter_column("item_code", existing_type=sa.String(64), type_=sa.String(32), existing_nullable=False)


def downgrade():
    with op.batch_alter_table("shop_listings") as batch:
        batch.alter_column("item_code", existing_type=sa.String(32), type_=sa.String(64), existing_nullable=False)
