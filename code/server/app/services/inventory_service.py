from __future__ import annotations

from sqlalchemy import and_
from sqlalchemy.orm import Session

from app.models.inventory import InventoryItem
from app.models.item import ItemDefinition
from app.models.player import Player


class InventoryError(Exception):
    pass


class ItemNotFound(InventoryError):
    pass


class NotEnoughQuantity(InventoryError):
    pass


class InvalidItemCode(InventoryError):
    pass


def validate_item_code(db: Session, item_code: str) -> ItemDefinition:
    item_def = db.query(ItemDefinition).filter(ItemDefinition.item_code == item_code).first()
    if not item_def:
        raise InvalidItemCode(f"Item code '{item_code}' does not exist in catalog")
    return item_def


def get_inventory(db: Session, player_id: int, location: str | None = None) -> list[InventoryItem]:
    query = db.query(InventoryItem).filter(InventoryItem.player_id == player_id)
    if location:
        query = query.filter(InventoryItem.location == location)
    return query.order_by(InventoryItem.item_code).all()


def add_item(db: Session, player_id: int, item_code: str, quantity: int = 1, location: str = "inventory") -> InventoryItem:
    # Validate item exists in catalog
    validate_item_code(db, item_code)

    existing = db.query(InventoryItem).filter(
        and_(
            InventoryItem.player_id == player_id,
            InventoryItem.item_code == item_code,
            InventoryItem.location == location,
        )
    ).first()

    if existing:
        existing.quantity += quantity
        db.commit()
        db.refresh(existing)
        return existing

    item = InventoryItem(
        player_id=player_id,
        item_code=item_code,
        quantity=quantity,
        location=location,
    )
    db.add(item)
    db.commit()
    db.refresh(item)
    return item


def remove_item(db: Session, player_id: int, item_code: str, quantity: int = 1, location: str = "inventory") -> InventoryItem | None:
    item = db.query(InventoryItem).filter(
        and_(
            InventoryItem.player_id == player_id,
            InventoryItem.item_code == item_code,
            InventoryItem.location == location,
        )
    ).first()

    if not item:
        raise ItemNotFound(f"Item {item_code} not found in inventory")

    if item.quantity < quantity:
        raise NotEnoughQuantity(
            f"Not enough {item_code}. Have {item.quantity}, need {quantity}"
        )

    item.quantity -= quantity

    if item.quantity <= 0:
        db.delete(item)
        db.commit()
        return None

    db.commit()
    db.refresh(item)
    return item


def transfer_item(
    db: Session, from_player_id: int, to_player_username: str, item_code: str, quantity: int
) -> tuple[InventoryItem | None, InventoryItem]:
    to_player = db.query(Player).filter(Player.username == to_player_username).first()
    if not to_player:
        raise InventoryError(f"Player {to_player_username} not found")

    if to_player.id == from_player_id:
        raise InventoryError("Cannot transfer to yourself")

    removed = remove_item(db, from_player_id, item_code, quantity)
    added = add_item(db, to_player.id, item_code, quantity)

    return removed, added


def has_item(db: Session, player_id: int, item_code: str, quantity: int = 1, location: str = "inventory") -> bool:
    item = db.query(InventoryItem).filter(
        and_(
            InventoryItem.player_id == player_id,
            InventoryItem.item_code == item_code,
            InventoryItem.location == location,
        )
    ).first()
    return item is not None and item.quantity >= quantity


def get_catalog(db: Session) -> list[ItemDefinition]:
    return db.query(ItemDefinition).order_by(ItemDefinition.category, ItemDefinition.name).all()


def get_catalog_by_season(db: Session, season: str) -> list[ItemDefinition]:
    return db.query(ItemDefinition).filter(
        (ItemDefinition.season == season) | (ItemDefinition.season == "all")
    ).order_by(ItemDefinition.name).all()