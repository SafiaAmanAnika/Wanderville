from sqlalchemy.orm import Session
from sqlalchemy import and_
from app.models.inventory import InventoryItem
from app.models.player import Player


class InventoryError(Exception):
    pass


class ItemNotFound(InventoryError):
    pass


class NotEnoughQuantity(InventoryError):
    pass


class ItemAlreadyExists(InventoryError):
    pass


def get_inventory(db: Session, player_id: int) -> list[InventoryItem]:
    return db.query(InventoryItem).filter(
        InventoryItem.player_id == player_id
    ).order_by(InventoryItem.item_type).all()


def add_item(db: Session, player_id: int, item_type: str, quantity: int = 1) -> InventoryItem:
    existing = db.query(InventoryItem).filter(
        and_(InventoryItem.player_id == player_id, InventoryItem.item_type == item_type)
    ).first()

    if existing:
        existing.quantity += quantity
        db.commit()
        db.refresh(existing)
        return existing

    item = InventoryItem(
        player_id=player_id,
        item_type=item_type,
        quantity=quantity,
    )
    db.add(item)
    db.commit()
    db.refresh(item)
    return item


def remove_item(db: Session, player_id: int, item_type: str, quantity: int = 1) -> InventoryItem:
    item = db.query(InventoryItem).filter(
        and_(InventoryItem.player_id == player_id, InventoryItem.item_type == item_type)
    ).first()

    if not item:
        raise ItemNotFound(f"Item {item_type} not found in inventory")

    if item.quantity < quantity:
        raise NotEnoughQuantity(
            f"Not enough {item_type}. Have {item.quantity}, need {quantity}"
        )

    item.quantity -= quantity

    if item.quantity <= 0:
        db.delete(item)
        db.commit()
        return None

    db.commit()
    db.refresh(item)
    return item


def transfer_item(db: Session, from_player_id: int, to_player_username: str, item_type: str, quantity: int) -> tuple[InventoryItem, InventoryItem]:
    to_player = db.query(Player).filter(Player.username == to_player_username).first()
    if not to_player:
        raise InventoryError(f"Player {to_player_username} not found")

    if to_player.id == from_player_id:
        raise InventoryError("Cannot transfer to yourself")

    removed = remove_item(db, from_player_id, item_type, quantity)
    added = add_item(db, to_player.id, item_type, quantity)

    return removed, added


def has_item(db: Session, player_id: int, item_type: str, quantity: int = 1) -> bool:
    item = db.query(InventoryItem).filter(
        and_(InventoryItem.player_id == player_id, InventoryItem.item_type == item_type)
    ).first()
    return item is not None and item.quantity >= quantity
