"""The level table, XP awards and unlock rules are one shared contract."""

import json
from pathlib import Path

import pytest
from sqlalchemy import select

from app.core.progression import (
    BASE_INVENTORY_SLOTS,
    FISH_XP_BY_ITEM,
    HARVEST_XP,
    ITEM_UNLOCK_LEVELS,
    LEVELS,
    LEVEL_AURA_REWARDS,
    MAX_LEVEL,
    FIRST_HARVEST_XP,
    level_for_xp,
    level_info,
    sells_for_xp,
    slot_capacity,
    unlock_level,
)
from app.modules.inventory.models import ItemDefinition
from app.modules.shop.models import ItemRule

CATALOG = json.loads(
    (Path(__file__).resolve().parents[2] / "app" / "db" / "catalog.json").read_text(
        encoding="utf-8"
    )
)
ITEMS = CATALOG["items"] if isinstance(CATALOG, dict) else CATALOG
CROP_CODES = [i["item_code"] for i in ITEMS if i.get("growth_time_seconds")]


def test_level_table_is_strictly_increasing():
    assert LEVELS[0] == (1, "Villager", 0, 3)
    assert [row[0] for row in LEVELS] == list(range(1, MAX_LEVEL + 1))
    xp = [row[2] for row in LEVELS]
    assert xp == sorted(xp) and xp[0] == 0
    assert all(row[3] > 0 for row in LEVELS)


@pytest.mark.parametrize(
    ("total_xp", "level"),
    [(0, 1), (999_999, MAX_LEVEL)] + [
        (threshold + delta, level - 1 if delta == -1 else level)
        for level, _, threshold, _ in LEVELS[1:]
        for delta in (-1, 0, 1)
    ],
)
def test_level_for_xp_boundaries(total_xp, level):
    assert level_for_xp(total_xp).level == level


def test_slot_capacity_is_cumulative_and_monotonic():
    assert slot_capacity(1) == BASE_INVENTORY_SLOTS + 3
    sizes = [slot_capacity(level) for level in range(1, MAX_LEVEL + 1)]
    assert sizes == sorted(sizes)
    assert level_info(1).cumulative_slots == 3
    assert level_info(MAX_LEVEL).cumulative_slots == sum(r[3] for r in LEVELS)


def test_level_titles_only_change_at_designed_levels():
    titles = [row[1] for row in LEVELS]
    assert titles == [
        "Villager", "Villager", "Farmer", "Farmer", "Farmer",
        "Settler", "Settler", "Settler", "Landkeeper", "Landkeeper",
    ]


def test_aura_rewards_are_authoritative_and_modest():
    assert LEVEL_AURA_REWARDS == {2: 25, 10: 100}
    # Rewards must never hand out more Aura than a full XP run earns by farming.
    common_yield = (2100 // (HARVEST_XP["common"] + FIRST_HARVEST_XP)) * 50
    assert sum(LEVEL_AURA_REWARDS.values()) < common_yield


def test_every_catalog_item_has_an_explicit_unlock_level():
    unknown = [
        item["item_code"]
        for item in ITEMS
        if item["item_code"] not in ITEM_UNLOCK_LEVELS
    ]
    assert unknown == []


def test_unlock_levels_match_the_documented_bands(db):
    bands = {
        1: ["paddy", "wheat"],
        2: ["barley", "oats", "sugarcane"],
        4: [
            "apple", "asparagus", "beetroot", "bell_pepper", "brussels_sprouts", "cabbage",
            "carrot", "green_bean", "kale", "lettuce", "onion", "pea", "potato", "pumpkin",
            "radish", "spinach", "strawberry", "sweet_corn", "turnip", "zucchini",
        ],
        8: ["moonflower", "rivermint", "sunbloom", "ancient_grain"],
    }
    for level, codes in bands.items():
        for code in codes:
            assert unlock_level(code) == level, code
            # A seed inherits its crop's level so both rows agree in the store.
            assert unlock_level(f"{code}_seed") == level, code


def test_seeded_rules_mirror_the_unlock_table(db):
    rows = db.execute(
        select(ItemRule.item_code, ItemRule.required_level, ItemDefinition.category)
        .join(ItemDefinition, ItemDefinition.item_code == ItemRule.item_code)
    ).all()
    assert rows
    for item_code, required_level, category in rows:
        expected = unlock_level(item_code)
        assert required_level == expected, (item_code, required_level, expected)
        if category in {"seed", "fishing_rod", "pet_item", "decoration"}:
            assert expected >= 1


def test_store_gear_unlocks_at_level_five(db):
    for code in ("basic_rod", "garden_lantern", "pet_biscuit"):
        rule = db.scalar(select(ItemRule).where(ItemRule.item_code == code))
        assert rule.required_level == 5


def test_only_gathered_produce_sells_for_xp():
    for category in ("general_crop", "spring_crop", "winter_crop", "rare_plant"):
        assert sells_for_xp(category) is True
    for category in ("seed", "fishing_rod", "pet_item", "decoration", "tool"):
        assert sells_for_xp(category) is False


def test_every_crop_defines_a_known_harvest_category(db):
    for code in CROP_CODES:
        definition = db.scalar(select(ItemDefinition).where(ItemDefinition.item_code == code))
        assert definition.harvest_category in HARVEST_XP
        assert definition.harvest_xp == HARVEST_XP[definition.harvest_category]


def test_fishing_xp_is_carried_per_item():
    for code, xp in FISH_XP_BY_ITEM.items():
        assert xp > 0
