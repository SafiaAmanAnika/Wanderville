import pytest
from sqlalchemy import select

from app.core.config import settings
from app.core.progression import (
    LEVEL_AURA_REWARDS,
    LEVELS,
    level_for_xp,
    slot_capacity,
)
from app.modules.economy.models import EconomyTransaction
from app.modules.economy.repository import EconomyRepository
from app.modules.economy.schemas import TransactionRequest
from app.modules.economy.service import EconomyService


@pytest.mark.parametrize("value", [0, -5, 1.2, True])
def test_reject_invalid_amounts(client, account, value):
    user = account()
    for path in ("earn", "spend"):
        assert (
            client.post(
                f"/economy/{path}", headers=user.headers, json={"amount": value}
            ).status_code
            == 422
        )
    assert (
        client.post(
            "/economy/xp/gain", headers=user.headers, json={"xp_amount": value}
        ).status_code
        == 422
    )


def test_insufficient_funds_ledger_and_isolation(client, account):
    first, second = account(), account("player_two")
    assert (
        client.post(
            "/economy/spend", headers=first.headers, json={"amount": 11}
        ).json()["error"]
        == "INSUFFICIENT_FUNDS"
    )
    client.post("/economy/earn", headers=first.headers, json={"amount": 50})
    client.post("/economy/spend", headers=first.headers, json={"amount": 20})
    history = client.get("/economy/transactions", headers=first.headers).json()["data"]
    assert [r["amount"] for r in history] == [-20, 50, 10]
    assert (
        client.get("/economy/", headers=second.headers).json()["data"]["taka_balance"]
        == 10
    )
    assert [
        r["amount"]
        for r in client.get("/economy/transactions", headers=second.headers).json()[
            "data"
        ]
    ] == [10]
    result = client.post(
        "/economy/xp/gain", headers=first.headers, json={"xp_amount": 250}
    ).json()["data"]
    # 250 lifetime XP lands on level 3 (floor 180, next floor 320).
    assert result["level"] == 3
    assert result["title"] == "Farmer"
    assert result["xp_floor"] == 180
    assert result["current_xp"] == 70
    assert result["xp_span"] == 140
    assert result["xp_to_next_level"] == 70
    assert result["max_level"] is False
    assert result["slot_increment"] == 9
    assert result["slot_capacity"] == 39
    # Level 2 crossed on the way, so its Aura reward is paid exactly once.
    assert [r["level"] for r in result["rewards"]] == [2]
    assert result["rewards"][0]["aura"] == LEVEL_AURA_REWARDS[2]
    balance = client.get("/economy/", headers=first.headers).json()["data"]
    assert balance["taka_balance"] == 40 + LEVEL_AURA_REWARDS[2]
    repeat = client.post(
        "/economy/xp/gain", headers=first.headers, json={"xp_amount": 250}
    ).json()["data"]
    assert repeat["rewards"] == []
    assert client.get("/economy/", headers=first.headers).json()["data"][
        "taka_balance"
    ] == balance["taka_balance"]
    # A plain read still reports the durable reward history.
    assert [
        r["level"] for r in client.get("/economy/xp", headers=first.headers).json()["data"]["rewards"]
    ] == [2]


def test_level_thresholds_titles_and_cap(client, account):
    user = account("level_ladder")
    samples = [0, 1] + [floor + offset for _, _, floor, _ in LEVELS[1:] for offset in (-1, 0, 1)]
    for total in samples:
        current = client.get("/economy/xp", headers=user.headers).json()["data"]
        gap = total - current["total_xp"]
        if gap:
            client.post(
                "/economy/xp/gain", headers=user.headers, json={"xp_amount": gap}
            )
        data = client.get("/economy/xp", headers=user.headers).json()["data"]
        expected = level_for_xp(total)
        assert (data["level"], data["title"]) == (expected.level, expected.title)
        assert data["slot_capacity"] == slot_capacity(expected.level)
        inventory = client.get("/inventory/", headers=user.headers).json()["data"]
        assert data["slot_capacity"] == inventory["capacity"]
        assert data["current_xp"] == total - expected.min_xp
        assert data["xp_span"] == expected.span_to_next
        assert all(item["required_level"] <= expected.level for item in data["unlocked_items"])
    top = client.get("/economy/xp", headers=user.headers).json()["data"]
    assert top["level"] == 10 and top["title"] == "Landkeeper"
    assert top["max_level"] is True and top["xp_to_next_level"] == 0
    assert top["slot_capacity"] == 76
    assert {r["level"] for r in top["rewards"]} == {2, 10}


def test_capacity_preserves_account_base_after_config_changes(client, account, db, monkeypatch):
    from app.modules.economy.models import PlayerExperience
    from app.modules.inventory.service import InventoryService

    monkeypatch.setattr(settings, "inventory_partition_slots", 44)
    user = account("capacity_owner")
    monkeypatch.setattr(settings, "inventory_partition_slots", 30)
    assert InventoryService(db).list(user.id).base_capacity == 44
    assert EconomyService(db).xp(user.id).slot_capacity == 47
    experience = db.get(PlayerExperience, user.id)
    # A migrated account may have a larger base, permanently retained after sales.
    experience.inventory_base_capacity = 180
    db.commit()
    assert InventoryService(db).list(user.id).capacity == 183
    assert EconomyService(db).xp(user.id).slot_capacity == 183


def test_level_reward_failure_rolls_back_xp_and_issuance(client, account, db, monkeypatch):
    from app.modules.economy.models import PlayerLevelReward

    user = account("rollback_level")
    def fail(*args, **kwargs):
        raise RuntimeError("reward ledger failure")
    monkeypatch.setattr(EconomyRepository, "record", fail)
    with pytest.raises(RuntimeError):
        from app.modules.economy.schemas import XPGainRequest
        EconomyService(db).gain_compatibility(user.id, XPGainRequest(xp_amount=80))
    db.expire_all()
    assert EconomyService(db).xp(user.id).total_xp == 0
    assert EconomyService(db).get(user.id).aura_balance == 10
    assert db.get(PlayerLevelReward, (user.id, 2)) is None


def test_multi_level_jump_pays_every_crossed_level_once(client, account):
    user = account("level_jump")
    response = client.post(
        "/economy/xp/gain", headers=user.headers, json={"xp_amount": 2100}
    )
    data = response.json()["data"]
    assert data["level"] == 10
    assert [(r["level"], r["aura"]) for r in data["rewards"]] == [
        (2, LEVEL_AURA_REWARDS[2]),
        (10, LEVEL_AURA_REWARDS[10]),
    ]
    balance = client.get("/economy/", headers=user.headers).json()["data"]
    assert balance["taka_balance"] == 10 + sum(LEVEL_AURA_REWARDS.values())
    # Replaying more XP must never pay a second time.
    client.post("/economy/xp/gain", headers=user.headers, json={"xp_amount": 1})
    assert client.get("/economy/", headers=user.headers).json()["data"][
        "taka_balance"
    ] == balance["taka_balance"]


def test_ledger_failure_rolls_back_balance(account, db, monkeypatch):
    user = account()

    def fail(*args, **kwargs):
        raise RuntimeError("ledger failed")

    monkeypatch.setattr(EconomyRepository, "record", fail)
    with pytest.raises(RuntimeError):
        EconomyService(db).change(user.id, TransactionRequest(amount=40), earn=True)
    assert EconomyService(db).get(user.id).aura_balance == 10
    assert [r.amount for r in db.scalars(select(EconomyTransaction))] == [10]


def test_arbitrary_rewards_disabled(client, account, monkeypatch):
    user = account()
    monkeypatch.setattr(settings, "wanderville_env", "production")
    assert (
        client.post(
            "/economy/earn", headers=user.headers, json={"amount": 5}
        ).status_code
        == 403
    )
    assert (
        client.post(
            "/economy/xp/gain", headers=user.headers, json={"xp_amount": 5}
        ).status_code
        == 403
    )
