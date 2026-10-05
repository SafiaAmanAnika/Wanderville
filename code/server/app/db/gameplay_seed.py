"""Reviewed gameplay defaults; balancing values are not prescribed by the SRS."""

from sqlalchemy import select
from app.core.progression import FISH_XP_BY_ITEM, unlock_level
from app.modules.inventory.models import ItemDefinition
from app.modules.shop.models import ItemRule, CollectionEntry
from app.modules.housing.models import HouseTier
from app.modules.fishing.models import FishingSpot
from app.modules.progression.models import GoalDefinition


def seed_gameplay(db):
    def upsert(model, key, values):
        row = db.get(model, key)
        if row:
            for k, v in values.items():
                setattr(row, k, v)
        else:
            db.add(model(**values))
        db.flush()

    crops = list(
        db.scalars(
            select(ItemDefinition).where(
                ItemDefinition.growth_time_seconds.is_not(None)
            )
        )
    )
    for crop in crops:
        upsert(
            ItemRule,
            crop.item_code,
            dict(
                item_code=crop.item_code,
                partition="crops",
                pet_food=crop.rarity == "common",
                required_level=unlock_level(crop.item_code),
            ),
        )
        code = f"{crop.item_code}_seed"
        old = db.scalar(select(ItemDefinition).where(ItemDefinition.item_code == code))
        values = dict(
            item_code=code,
            name=f"{crop.name} Seeds",
            category="seed",
            max_stack=99,
            buy_value=max(2, crop.sell_value // 2),
            sell_value=1,
            season=crop.season,
            rarity=crop.rarity,
            description=f"Plant to grow {crop.name}.",
            # A seed is not a harvest: only the crop it grows pays harvest XP.
            harvest_category=None,
            harvest_xp=0,
        )
        if old is None:
            db.add(ItemDefinition(**values))
            db.flush()
        else:
            # Re-seed so an existing row stops claiming a harvest category.
            for field, value in values.items():
                setattr(old, field, value)
        upsert(
            ItemRule,
            code,
            dict(
                item_code=code,
                partition="seeds",
                harvest_code=crop.item_code,
                # A seed can never be planted before the crop it grows.
                required_level=unlock_level(crop.item_code),
            ),
        )
    definitions = [
        ("river_carp", "River Carp", "fish", None, 12, "common", "fish", {}),
        ("golden_carp", "Golden Carp", "fish", None, 60, "rare", "fish", {}),
        (
            "lake_pearl",
            "Lake Pearl",
            "rare_material",
            None,
            90,
            "rare",
            "rare_materials",
            {},
        ),
        (
            "basic_rod",
            "Basic Fishing Rod",
            "tool",
            10,
            2,
            "common",
            "tools",
            {"fishing_rod": True},
        ),
        (
            "pet_biscuit",
            "Pet Biscuit",
            "pet_food",
            5,
            1,
            "common",
            "tools",
            {"pet_food": True},
        ),
        (
            "pet_ribbon",
            "Pet Ribbon",
            "accessory",
            25,
            5,
            "common",
            "tools",
            {"pet_accessory": True},
        ),
        (
            "garden_lantern",
            "Garden Lantern",
            "decoration",
            30,
            5,
            "common",
            "houses",
            {},
        ),
    ]
    for code, name, category, buy, sell, rarity, partition, flags in definitions:
        if (
            db.scalar(select(ItemDefinition).where(ItemDefinition.item_code == code))
            is None
        ):
            db.add(
                ItemDefinition(
                    item_code=code,
                    name=name,
                    category=category,
                    buy_value=buy,
                    sell_value=sell,
                    rarity=rarity,
                    placeable=category == "decoration",
                    max_stack=99,
                    description=name,
                )
            )
            db.flush()
        upsert(
            ItemRule,
            code,
            dict(
                item_code=code,
                partition=partition,
                required_level=unlock_level(code),
                **flags,
            ),
        )
    # Catalog-driven harvest XP also covers fish and gathered rare materials.
    for code, xp in FISH_XP_BY_ITEM.items():
        definition = db.scalar(
            select(ItemDefinition).where(ItemDefinition.item_code == code)
        )
        if definition is not None:
            definition.harvest_xp = xp
    for tier, name, cost, level in [
        (1, "Starter House", 0, 1),
        (2, "Cozy Cottage", 100, 2),
        (3, "Campus Villa", 300, 4),
    ]:
        upsert(
            HouseTier, tier, dict(tier=tier, name=name, cost=cost, required_level=level)
        )
    upsert(
        FishingSpot,
        "campus_lake",
        dict(code="campus_lake", name="Campus Lake", freezes_in_winter=True),
    )
    for code, kind, title, event, target, reward in [
        ("first_harvest", "achievement", "Harvest your first crop", "harvest", 1, 10),
        ("harvest_100", "achievement", "Harvest 100 crops", "harvest", 100, 100),
        ("first_catch", "achievement", "Catch your first fish", "catch", 1, 10),
        ("daily_plant", "daily", "Plant 5 seeds", "plant", 5, 10),
        ("daily_harvest", "daily", "Harvest 3 crops", "harvest", 3, 15),
        ("daily_fish", "daily", "Catch 3 fish", "catch", 3, 15),
    ]:
        upsert(
            GoalDefinition,
            code,
            dict(
                code=code,
                kind=kind,
                title=title,
                event=event,
                target=target,
                aura_reward=reward,
            ),
        )
    # Seed is also a safe backfill for already-owned collectible items.
    from app.modules.inventory.models import InventoryItem

    for pid, code in db.execute(
        select(InventoryItem.player_id, InventoryItem.item_code)
    ):
        if db.get(CollectionEntry, (pid, code)) is None:
            db.add(CollectionEntry(player_id=pid, item_code=code))
