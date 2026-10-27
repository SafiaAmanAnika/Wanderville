"""Explicit reference seeding: python -m app.db.seed."""

import json
from pathlib import Path

from sqlalchemy import select, func

from app.db import model_registry  # noqa: F401
from app.db.gameplay_seed import seed_gameplay
from app.db.session import SessionLocal, transaction
from app.modules.inventory.models import ItemDefinition
from app.modules.world.models import WorldState

SEED_ITEMS = json.loads(Path(__file__).with_name("catalog.json").read_text())



def retire_removed_crops(db):
    """Delete crops and seeds that catalog.json no longer defines.

    The upsert above only ever adds and updates, so a crop dropped from the
    catalog would linger in the store and the seed picker forever. Only crops
    and their seeds are considered: fish, tools and anything seeded elsewhere
    are left alone.
    """
    keep = {values["item_code"] for values in SEED_ITEMS}
    keep |= {f"{code}_seed" for code in keep}
    stale = [
        row.item_code
        for row in db.scalars(select(ItemDefinition))
        if row.item_code not in keep
        and (row.growth_time_seconds is not None or row.item_code.endswith("_seed"))
    ]
    if not stale:
        return []
    # Clear every row that points at them first, or the delete trips a foreign key.
    for table in reversed(ItemDefinition.metadata.sorted_tables):
        if table.name == ItemDefinition.__tablename__:
            continue
        for name in ("item_code", "crop_item_code", "wanted_code", "offered_code", "rod_code"):
            column = table.columns.get(name)
            if column is not None:
                db.execute(table.delete().where(column.in_(stale)))
    db.execute(
        ItemDefinition.__table__.delete().where(ItemDefinition.item_code.in_(stale))
    )
    return stale


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
        retired = retire_removed_crops(db)
        if retired:
            print(f"Retired {len(retired)} item(s) no longer in catalog.json: {', '.join(sorted(retired))}")
        db.flush()
        seed_gameplay(db)


def main():
    with SessionLocal() as db:
        seed_reference_data(db)
        count = db.scalar(select(func.count()).select_from(ItemDefinition))
    print(
        f"Seeded {count} item definitions and gameplay reference data; preserved world clock."
    )


if __name__ == "__main__":
    main()
