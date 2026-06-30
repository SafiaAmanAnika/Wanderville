from __future__ import annotations

from sqlalchemy.orm import Session

from app.models.economy import PlayerEconomy
from app.models.experience import PlayerExperience


class EconomyError(Exception):
    pass


class InsufficientFunds(EconomyError):
    pass


def get_or_create_economy(db: Session, player_id: int) -> PlayerEconomy:
    economy = db.query(PlayerEconomy).filter(PlayerEconomy.player_id == player_id).first()
    if not economy:
        economy = PlayerEconomy(player_id=player_id)
        db.add(economy)
        db.commit()
        db.refresh(economy)
    return economy


def add_taka(db: Session, player_id: int, amount: int, description: str | None = None) -> PlayerEconomy:
    economy = get_or_create_economy(db, player_id)
    economy.taka_balance += amount
    economy.total_earned += amount
    db.commit()
    db.refresh(economy)
    return economy


def spend_taka(db: Session, player_id: int, amount: int, description: str | None = None) -> PlayerEconomy:
    economy = get_or_create_economy(db, player_id)
    if economy.taka_balance < amount:
        raise InsufficientFunds(f"Need {amount} taka, have {economy.taka_balance}")
    economy.taka_balance -= amount
    economy.total_spent += amount
    db.commit()
    db.refresh(economy)
    return economy


def get_or_create_xp(db: Session, player_id: int) -> PlayerExperience:
    xp = db.query(PlayerExperience).filter(PlayerExperience.player_id == player_id).first()
    if not xp:
        xp = PlayerExperience(player_id=player_id)
        db.add(xp)
        db.commit()
        db.refresh(xp)
    return xp


def add_xp(db: Session, player_id: int, amount: int) -> PlayerExperience:
    xp = get_or_create_xp(db, player_id)
    xp.current_xp += amount
    xp.total_xp += amount

    # Level up logic
    while xp.current_xp >= xp.xp_to_next_level:
        xp.current_xp -= xp.xp_to_next_level
        xp.level += 1
        xp.xp_to_next_level = int(xp.xp_to_next_level * 1.5)

    db.commit()
    db.refresh(xp)
    return xp