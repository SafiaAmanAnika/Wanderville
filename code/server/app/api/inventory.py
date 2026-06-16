from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.database import get_db
from app.deps.auth import get_current_player_id
from app.schemas.inventory import (
    AddItemRequest,
    InventoryItemResponse,
    InventoryListResponse,
    RemoveItemRequest,
    TransferItemRequest,
)
from app.schemas.responses import Envelope
from app.services import inventory_service

router = APIRouter(prefix="/inventory", tags=["inventory"])


@router.get("/", response_model=Envelope[InventoryListResponse])
def get_inventory(
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    items = inventory_service.get_inventory(db, player_id)
    total_quantity = sum(item.quantity for item in items)

    data = InventoryListResponse(
        items=[InventoryItemResponse.model_validate(item) for item in items],
        total_items=len(items),
        total_quantity=total_quantity,
    )

    return {
        "success": True,
        "data": data.model_dump(),
        "message": "Inventory retrieved",
    }


@router.post("/add", response_model=Envelope[InventoryItemResponse])
def add_item(
    req: AddItemRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    try:
        item = inventory_service.add_item(db, player_id, req.item_type, req.quantity)
        data = InventoryItemResponse.model_validate(item)
        return {
            "success": True,
            "data": data.model_dump(),
            "message": f"Added {req.quantity} {req.item_type}",
        }
    except inventory_service.InventoryError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/remove", response_model=Envelope[InventoryItemResponse | None])
def remove_item(
    req: RemoveItemRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    try:
        item = inventory_service.remove_item(db, player_id, req.item_type, req.quantity)
        if item is None:
            return {
                "success": True,
                "data": None,
                "message": f"Removed all {req.item_type}",
            }
        data = InventoryItemResponse.model_validate(item)
        return {
            "success": True,
            "data": data.model_dump(),
            "message": f"Removed {req.quantity} {req.item_type}",
        }
    except inventory_service.InventoryError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/transfer", response_model=Envelope[dict])
def transfer_item(
    req: TransferItemRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    try:
        _, received = inventory_service.transfer_item(
            db, player_id, req.to_player_username, req.item_type, req.quantity
        )
        return {
            "success": True,
            "data": {
                "transferred": req.item_type,
                "quantity": req.quantity,
                "to": req.to_player_username,
            },
            "message": f"Sent {req.quantity} {req.item_type} to {req.to_player_username}",
        }
    except inventory_service.InventoryError as e:
        raise HTTPException(status_code=400, detail=str(e))
