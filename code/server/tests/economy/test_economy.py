import pytest
from sqlalchemy import select

from app.core.config import settings
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
        client.post("/economy/spend", headers=first.headers, json={"amount": 1}).json()[
            "error"
        ]
        == "INSUFFICIENT_FUNDS"
    )
    client.post("/economy/earn", headers=first.headers, json={"amount": 50})
    client.post("/economy/spend", headers=first.headers, json={"amount": 20})
    history = client.get("/economy/transactions", headers=first.headers).json()["data"]
    assert [r["amount"] for r in history] == [-20, 50]
    assert (
        client.get("/economy/", headers=second.headers).json()["data"]["taka_balance"]
        == 0
    )
    assert (
        client.get("/economy/transactions", headers=second.headers).json()["data"] == []
    )
    result = client.post(
        "/economy/xp/gain", headers=first.headers, json={"xp_amount": 250}
    )
    assert result.json()["data"]["level"] == 3
    assert result.json()["data"]["current_xp"] == 0
    assert result.json()["data"]["xp_to_next_level"] == 225


def test_ledger_failure_rolls_back_balance(account, db, monkeypatch):
    user = account()

    def fail(*args, **kwargs):
        raise RuntimeError("ledger failed")

    monkeypatch.setattr(EconomyRepository, "record", fail)
    with pytest.raises(RuntimeError):
        EconomyService(db).change(user.id, TransactionRequest(amount=40), earn=True)
    assert EconomyService(db).get(user.id).aura_balance == 0
    assert db.scalar(select(EconomyTransaction)) is None


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
