import pytest
from sqlalchemy import select

from app.core.config import settings
from app.core.exceptions import AppError
from app.modules.inventory.models import InventoryItem
from app.modules.inventory.schemas import TransferRequest
from app.modules.inventory.service import InventoryService


@pytest.mark.parametrize("quantity", [0, -1, 1.5, True])
def test_invalid_quantities(client, account, quantity):
    user = account()
    for path in ("add", "remove"):
        assert (
            client.post(
                f"/inventory/{path}",
                headers=user.headers,
                json={"item_code": "wheat", "quantity": quantity},
            ).status_code
            == 422
        )


def test_stacks_removal_and_isolation(client, account):
    first, second = account(), account("player_two")
    for _ in range(2):
        assert (
            client.post(
                "/inventory/add",
                headers=first.headers,
                json={"item_code": "wheat", "quantity": 2},
            ).status_code
            == 200
        )
    items = client.get("/inventory/", headers=first.headers).json()["data"]
    assert items["total_items"] == 1 and items["total_quantity"] == 4
    assert (
        client.get("/inventory/", headers=second.headers).json()["data"]["items"] == []
    )
    assert (
        client.post(
            "/inventory/remove",
            headers=first.headers,
            json={"item_code": "wheat", "quantity": 5},
        ).json()["error"]
        == "INSUFFICIENT_INVENTORY"
    )
    assert (
        client.post(
            "/inventory/remove",
            headers=first.headers,
            json={"item_code": "wheat", "quantity": 4},
        ).json()["data"]
        is None
    )
    assert (
        client.post(
            "/inventory/add",
            headers=first.headers,
            json={"item_code": "does_not_exist"},
        ).json()["error"]
        == "INVALID_ITEM"
    )
    assert (
        client.post(
            "/inventory/add", headers=first.headers, json={"item_type": "wheat"}
        ).status_code
        == 200
    )


def test_transfer_success_and_rollback(client, account, db, monkeypatch):
    sender, receiver = account(), account("receiver")
    client.post(
        "/inventory/add",
        headers=sender.headers,
        json={"item_code": "wheat", "quantity": 3},
    )
    request = TransferRequest(
        to_player_username="receiver", item_code="wheat", quantity=2
    )
    service = InventoryService(db)
    original = InventoryService.add_internal

    def fail(*args, **kwargs):
        raise RuntimeError("receiver write failed")

    monkeypatch.setattr(InventoryService, "add_internal", fail)
    with pytest.raises(RuntimeError):
        service.transfer(sender.id, request)
    assert (
        db.scalar(
            select(InventoryItem).where(InventoryItem.player_id == sender.id)
        ).quantity
        == 3
    )
    assert (
        db.scalar(select(InventoryItem).where(InventoryItem.player_id == receiver.id))
        is None
    )
    monkeypatch.setattr(InventoryService, "add_internal", original)
    service.transfer(sender.id, request)
    assert (
        db.scalar(
            select(InventoryItem).where(InventoryItem.player_id == sender.id)
        ).quantity
        == 1
    )
    assert (
        db.scalar(
            select(InventoryItem).where(InventoryItem.player_id == receiver.id)
        ).quantity
        == 2
    )


def test_transfer_full_stack_rolls_back_sender(client, account, db):
    sender, receiver = account(), account("receiver")
    client.post(
        "/inventory/add",
        headers=sender.headers,
        json={"item_code": "wheat", "quantity": 3},
    )
    client.post(
        "/inventory/add",
        headers=receiver.headers,
        json={"item_code": "wheat", "quantity": 99},
    )
    with pytest.raises(AppError, match="capacity"):
        InventoryService(db).transfer(
            sender.id,
            TransferRequest(
                to_player_username="receiver", item_code="wheat", quantity=2
            ),
        )
    assert InventoryService(db).list(sender.id).total_quantity == 3


def test_arbitrary_inventory_disabled_in_production(client, account, monkeypatch):
    user = account()
    monkeypatch.setattr(settings, "wanderville_env", "production")
    assert (
        client.post(
            "/inventory/add", headers=user.headers, json={"item_code": "wheat"}
        ).status_code
        == 403
    )
