import logging
from sqlalchemy.orm import Session
from app.models.item import ItemDefinition

logger = logging.getLogger(__name__)

SEED_ITEMS = [
    # General Purpose Crops
    {"item_code": "paddy", "name": "Paddy", "category": "general_crop", "growth_time_seconds": 30, "sell_value": 10, "xp_reward": 5, "season": "all"},
    {"item_code": "wheat", "name": "Wheat", "category": "general_crop", "growth_time_seconds": 45, "sell_value": 12, "xp_reward": 5, "season": "all"},
    {"item_code": "sugarcane", "name": "Sugarcane", "category": "general_crop", "growth_time_seconds": 50, "sell_value": 15, "xp_reward": 5, "season": "all"},
    {"item_code": "corn", "name": "Corn", "category": "general_crop", "growth_time_seconds": 170, "sell_value": 20, "xp_reward": 8, "season": "summer"},
    {"item_code": "cotton", "name": "Cotton", "category": "general_crop", "growth_time_seconds": 140, "sell_value": 18, "xp_reward": 8, "season": "summer"},
    # Summer
    {"item_code": "sweet_corn", "name": "Sweet Corn", "category": "summer_crop", "growth_time_seconds": 180, "sell_value": 25, "xp_reward": 10, "season": "summer"},
    {"item_code": "bell_pepper", "name": "Bell Pepper", "category": "summer_crop", "growth_time_seconds": 150, "sell_value": 22, "xp_reward": 10, "season": "summer"},
    {"item_code": "green_bean", "name": "Green Bean", "category": "summer_crop", "growth_time_seconds": 120, "sell_value": 18, "xp_reward": 10, "season": "summer"},
    # Autumn
    {"item_code": "pumpkin", "name": "Pumpkin", "category": "autumn_crop", "growth_time_seconds": 200, "sell_value": 30, "xp_reward": 10, "season": "autumn"},
    {"item_code": "apple", "name": "Apple", "category": "autumn_crop", "growth_time_seconds": 300, "sell_value": 35, "xp_reward": 10, "season": "autumn"},
    {"item_code": "turnip", "name": "Turnip", "category": "autumn_crop", "growth_time_seconds": 140, "sell_value": 15, "xp_reward": 10, "season": "autumn"},
    # Winter
    {"item_code": "potato", "name": "Potato", "category": "winter_crop", "growth_time_seconds": 220, "sell_value": 20, "xp_reward": 10, "season": "winter"},
    {"item_code": "carrot", "name": "Carrot", "category": "winter_crop", "growth_time_seconds": 160, "sell_value": 16, "xp_reward": 10, "season": "winter"},
    {"item_code": "cabbage", "name": "Cabbage", "category": "winter_crop", "growth_time_seconds": 190, "sell_value": 18, "xp_reward": 10, "season": "winter"},
    {"item_code": "strawberry", "name": "Strawberry", "category": "winter_crop", "growth_time_seconds": 240, "sell_value": 28, "xp_reward": 10, "season": "winter"},
    # Spring
    {"item_code": "lettuce", "name": "Lettuce", "category": "spring_crop", "growth_time_seconds": 100, "sell_value": 14, "xp_reward": 10, "season": "spring"},
    {"item_code": "pea", "name": "Pea", "category": "spring_crop", "growth_time_seconds": 130, "sell_value": 16, "xp_reward": 10, "season": "spring"},
    {"item_code": "radish", "name": "Radish", "category": "spring_crop", "growth_time_seconds": 90, "sell_value": 12, "xp_reward": 10, "season": "spring"},
    # Rare Plants
    {"item_code": "moonflower", "name": "Moonflower", "category": "rare_plant", "growth_time_seconds": 600, "sell_value": 100, "xp_reward": 30, "season": "all", "rarity": "rare"},
    {"item_code": "rivermint", "name": "Rivermint", "category": "rare_plant", "growth_time_seconds": 480, "sell_value": 80, "xp_reward": 25, "season": "all", "rarity": "rare"},
    {"item_code": "sunbloom", "name": "Sunbloom", "category": "rare_plant", "growth_time_seconds": 540, "sell_value": 90, "xp_reward": 25, "season": "all", "rarity": "rare"},
    {"item_code": "ancient_grain", "name": "Ancient Grain", "category": "rare_plant", "growth_time_seconds": 720, "sell_value": 120, "xp_reward": 30, "season": "all", "rarity": "epic"},
]


def seed_item_definitions(db: Session) -> None:
    existing = {item.item_code for item in db.query(ItemDefinition).all()}
    for data in SEED_ITEMS:
        if data["item_code"] not in existing:
            db.add(ItemDefinition(**data))
            logger.info(f"Seeded item: {data['item_code']}")
    db.commit()
    logger.info("Item definitions seeding complete.")