"""Single source of truth for level thresholds, XP awards and slot capacity.

The client never invents these numbers; `/economy/xp` and `/inventory/` report
them so the HUD, seed picker and store all read the same authoritative values.
"""

from dataclasses import dataclass

# ── Ten-level progression ────────────────────────────────────────────
# Cumulative lifetime XP thresholds, plus the inventory slots each level adds.
LEVELS: tuple[tuple[int, str, int, int], ...] = (
    (1, "Villager", 0, 3),
    (2, "Villager", 80, 3),
    (3, "Farmer", 180, 3),
    (4, "Farmer", 320, 3),
    (5, "Farmer", 500, 5),
    (6, "Settler", 750, 5),
    (7, "Settler", 1050, 5),
    (8, "Settler", 1400, 5),
    (9, "Landkeeper", 1800, 7),
    (10, "Landkeeper", 2100, 7),
)
MAX_LEVEL = LEVELS[-1][0]

# Balancing choice: modest Aura at level 2 (re-buy basics) and level 10
# (the only level with no new unlock to offer). No invented items or currencies.
LEVEL_AURA_REWARDS: dict[int, int] = {2: 25, 10: 100}


@dataclass(frozen=True)
class LevelInfo:
    level: int
    title: str
    min_xp: int
    slot_increment: int
    cumulative_slots: int

    @property
    def next_min_xp(self) -> int | None:
        # LEVELS[i].level == i + 1, so the next threshold sits at index `level`.
        return LEVELS[self.level][2] if self.level < len(LEVELS) else None

    @property
    def span_to_next(self) -> int:
        nxt = self.next_min_xp
        return 0 if nxt is None else nxt - self.min_xp


_BY_LEVEL = {
    row[0]: LevelInfo(
        level=row[0],
        title=row[1],
        min_xp=row[2],
        slot_increment=row[3],
        cumulative_slots=sum(r[3] for r in LEVELS[: index + 1]),
    )
    for index, row in enumerate(LEVELS)
}


def level_info(level: int) -> LevelInfo:
    """Clamp to the highest defined level; there is no level eleven."""
    return _BY_LEVEL[max(1, min(int(level), MAX_LEVEL))]


def level_for_xp(total_xp: int) -> LevelInfo:
    """Highest threshold reached; lifetime XP is never reduced."""
    xp = max(0, int(total_xp))
    reached = LEVELS[0]
    for row in LEVELS:
        if xp >= row[2]:
            reached = row
        else:
            break
    return _BY_LEVEL[reached[0]]


def xp_progress(total_xp: int) -> dict:
    """Everything the HUD needs to render level, title and progress."""
    xp = max(0, int(total_xp))
    info = level_for_xp(xp)
    next_min = info.next_min_xp
    return {
        "level": info.level,
        "title": info.title,
        "max_level": next_min is None,
        "current_xp": max(0, xp - info.min_xp),
        "xp_to_next_level": 0 if next_min is None else next_min - xp,
        "xp_span": info.span_to_next,
        "xp_floor": info.min_xp,
    }


# ── Inventory capacity ───────────────────────────────────────────────
# effective capacity = preserved base capacity + cumulative level increments,
# never below the stacks a player already owns (capacity is never confiscated).
BASE_INVENTORY_SLOTS = 30


def slot_capacity(level: int, base: int = BASE_INVENTORY_SLOTS) -> int:
    return base + level_info(level).cumulative_slots


def effective_capacity(level: int, occupied: int, base: int = BASE_INVENTORY_SLOTS) -> int:
    return max(slot_capacity(level, base), int(occupied))


# ── XP awards ────────────────────────────────────────────────────────
# Every crop stores exactly one harvest_xp from its category in the catalog,
# so a multi-tagged item can never combine two categories.
HARVEST_XP: dict[str, int] = {"common": 5, "seasonal": 10, "rare": 20, "magical": 30}
HARVEST_CATEGORY_XP = {name: value for name, value in HARVEST_XP.items()}

# One-time bonus for the first harvest of each crop species, per player.
FIRST_HARVEST_XP = 15

# Balancing choice: no explicit planting XP existed before, so a small flat
# default is used and kept strictly separate from the crop's harvest reward.
DEFAULT_PLANT_XP = 1

SELL_XP_PER_UNIT = 5
HOUSE_UPGRADE_XP = 20
FISH_XP = {"normal": 8, "rare": 20, "rare_material": 25}
# Same values as FISH_XP, keyed by item so the catalog can carry them per item.
FISH_XP_BY_ITEM = {"river_carp": 8, "golden_carp": 20, "lake_pearl": 25}


def sells_for_xp(category: str) -> bool:
    """Only gathered produce pays sale XP; store stock cannot be XP farmed.

    The category names are the catalog's own, so a newly tagged item is either
    explicitly listed here or deliberately excluded.
    """
    return category in {
        "crop",
        "general_crop",
        "spring_crop",
        "summer_crop",
        "autumn_crop",
        "winter_crop",
        "rare_plant",
        "produce",
        "fish",
        "rare_material",
    }


# ── Item unlock levels ───────────────────────────────────────────────
# The explicit item-to-required-level mapping. `gameplay_seed` copies these into
# ItemRule.required_level, the single authority the seed picker and store read.
#  1 basics | 2 extra all-season basics | 4 seasonal crops | 5 store gear
#  8 rare/special crops
ITEM_UNLOCK_LEVELS: dict[str, int] = {
    "paddy": 1,
    "wheat": 1,
    "sugarcane": 2,
    "corn": 2,
    "cotton": 2,
    "lettuce": 4,
    "pea": 4,
    "radish": 4,
    "bell_pepper": 4,
    "green_bean": 4,
    "sweet_corn": 4,
    "apple": 4,
    "pumpkin": 4,
    "turnip": 4,
    "cabbage": 4,
    "carrot": 4,
    "potato": 4,
    "strawberry": 4,
    "moonflower": 8,
    "rivermint": 8,
    "sunbloom": 8,
    "ancient_grain": 8,
    # Store item types unlock at level 5 alongside the fishing/housing gear.
    "basic_rod": 5,
    "pet_biscuit": 5,
    "pet_ribbon": 5,
    "garden_lantern": 5,
    "river_carp": 5,
    "golden_carp": 5,
    "lake_pearl": 5,
}


def unlock_level(item_code: str) -> int:
    if item_code in ITEM_UNLOCK_LEVELS:
        return ITEM_UNLOCK_LEVELS[item_code]
    if item_code.endswith("_seed"):
        return unlock_level(item_code[: -len("_seed")])
    return 1