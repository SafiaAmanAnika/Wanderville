"""Explicit reference seeding: python -m app.db.seed."""

import json
from pathlib import Path

from sqlalchemy import select

from app.db import model_registry  # noqa: F401
from app.db.session import SessionLocal, transaction
from app.modules.inventory.models import ItemDefinition
from app.modules.world.models import WorldState

SEED_ITEMS = json.loads(Path(__file__).with_name("catalog.json").read_text())


def seed_reference_data(db):
    """Idempotent upsert. Preserve unrelated items and the running world clock."""
    with transaction(db):
        existing = {row.item_code: row for row in db.scalars(select(ItemDefinition))}
        for values in SEED_ITEMS:
            if values["item_code"] in existing:
                for field, value in values.items():
                    setattr(existing[values["item_code"]], field, value)
            else:
                db.add(ItemDefinition(**values))
        if db.get(WorldState, 1) is None:
            db.add(WorldState(id=1))
        db.flush()


def main():
    with SessionLocal() as db:
        seed_reference_data(db)
    print(f"Seeded {len(SEED_ITEMS)} item definitions and ensured global world state.")


if __name__ == "__main__":
    main()
