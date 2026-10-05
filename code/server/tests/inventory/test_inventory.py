import pytest
from sqlalchemy import select

from app.core.config import settings
from app.core.exceptions import AppError
from app.core.progression import slot_capacity
from app.modules.inventory.models import InventoryItem, ItemDefinition
from app.modules.inventory.schemas import ItemRequest, TransferRequest
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


def test_one_item_spills_into_several_stacks(client, account, db):
    user = account()
    InventoryService(db).add_compatibility(
        user.id, ItemRequest(item_code="wheat", quantity=250)
    )
    view = InventoryService(db).list(user.id)
    # max_stack for wheat is 99, so 250 units need three occupied slots.
    assert view.total_items == 3
    assert view.total_quantity == 250
    assert view.used_slots == 3
    quantities = sorted(
        db.scalars(
            select(InventoryItem.quantity).where(InventoryItem.player_id == user.id)
        )
    )
    assert quantities == [52, 99, 99]
    stack_numbers = sorted(
        db.scalars(
            select(InventoryItem.stack_no).where(InventoryItem.player_id == user.id)
        )
    )
    assert stack_numbers == [0, 1, 2]


def test_adding_tops_up_the_partial_stack_before_opening_a_new_one(client, account, db):
    user = account()
    InventoryService(db).add_compatibility(
        user.id, ItemRequest(item_code="wheat", quantity=99)
    )
    InventoryService(db).add_compatibility(
        user.id, ItemRequest(item_code="wheat", quantity=99)
    )
    assert InventoryService(db).list(user.id).used_slots == 2
    InventoryService(db).add_compatibility(
        user.id, ItemRequest(item_code="wheat", quantity=5)
    )
    view = InventoryService(db).list(user.id)
    # The 100th unit has nowhere to merge, so it becomes a third stack.
    assert view.used_slots == 3
    assert view.total_quantity == 203


def test_removal_drains_across_stacks_and_frees_slots(client, account, db):
    user = account()
    InventoryService(db).add_compatibility(
        user.id, ItemRequest(item_code="wheat", quantity=250)
    )
    InventoryService(db).remove(user.id, ItemRequest(item_code="wheat", quantity=150))
    view = InventoryService(db).list(user.id)
    assert view.total_quantity == 100
    assert view.used_slots == 2
    InventoryService(db).remove(user.id, ItemRequest(item_code="wheat", quantity=100))
    assert InventoryService(db).list(user.id).used_slots == 0


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


def test_transfer_to_a_full_receiver_rolls_back_sender(client, account, db):
    sender, receiver = account(), account("receiver")
    client.post(
        "/inventory/add",
        headers=sender.headers,
        json={"item_code": "wheat", "quantity": 3},
    )
    # Every level 1 slot is taken by a distinct stack, so the incoming wheat
    # has nowhere to go and no partial stack can absorb it.
    codes = [
        row
        for row in db.scalars(
            select(ItemDefinition.item_code).order_by(ItemDefinition.item_code)
        )
        if row != "wheat"
    ]
    for code in codes[: slot_capacity(1)]:
        InventoryService(db).add_internal(receiver.id, code)
    db.commit()
    receiver_view = InventoryService(db).list(receiver.id)
    assert receiver_view.used_slots == slot_capacity(1)
    assert receiver_view.total_items == slot_capacity(1)

    with pytest.raises(AppError) as failure:
        InventoryService(db).transfer(
            sender.id,
            TransferRequest(
                to_player_username="receiver", item_code="wheat", quantity=2
            ),
        )
    assert failure.value.code == "INVENTORY_FULL"
    # The sender keeps everything and the receiver gains nothing.
    assert InventoryService(db).list(sender.id).total_quantity == 3
    assert InventoryService(db).list(receiver.id).total_items == slot_capacity(1)


def test_arbitrary_inventory_disabled_in_production(client, account, monkeypatch):
    user = account()
    monkeypatch.setattr(settings, "wanderville_env", "production")
    assert (
        client.post(
            "/inventory/add", headers=user.headers, json={"item_code": "wheat"}
        ).status_code
        == 403
    )


def test_full_inventory_accepts_partial_stack_only_and_rollback_is_atomic(client, account, db):
    user = account()
    service = InventoryService(db)
    service.add_compatibility(user.id, ItemRequest(item_code="wheat", quantity=95))
    codes = [code for code in db.scalars(select(ItemDefinition.item_code)) if code != "wheat"]
    for code in codes[:service.capacity(user.id) - 1]:
        service.add_internal(user.id, code)
    db.commit()
    assert service.list(user.id).used_slots == service.capacity(user.id)
    # This request can fill four units but cannot fit the fifth: all roll back.
    refused = client.post("/inventory/add", headers=user.headers, json={"item_code": "wheat", "quantity": 5})
    assert refused.json()["error"] == "INVENTORY_FULL"
    assert service.repo.stack(user.id, "wheat").quantity == 95
    accepted = client.post("/inventory/add", headers=user.headers, json={"item_code": "wheat", "quantity": 4})
    assert accepted.status_code == 200
    assert service.repo.stack(user.id, "wheat").quantity == 99
    assert service.list(user.id).used_slots == service.capacity(user.id)
