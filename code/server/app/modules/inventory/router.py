from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.responses import Envelope, success
from app.db.session import get_db
from app.modules.auth.dependencies import get_current_player_id
from app.modules.inventory.schemas import (
    InventoryItemResponse,
    InventoryListResponse,
    ItemDefinitionResponse,
    ItemRequest,
    TransferRequest,
)
from app.modules.inventory.service import InventoryService

router = APIRouter(prefix="/inventory", tags=["inventory"])


@router.get("/", response_model=Envelope[InventoryListResponse])
def inventory(
    player_id: int = Depends(get_current_player_id), db: Session = Depends(get_db)
):
    return success(InventoryService(db).list(player_id))


@router.get("/catalog", response_model=Envelope[list[ItemDefinitionResponse]])
def catalog(
    _player_id: int = Depends(get_current_player_id), db: Session = Depends(get_db)
):
    return success(InventoryService(db).catalog())


@router.get("/catalog/{season}", response_model=Envelope[list[ItemDefinitionResponse]])
def seasonal_catalog(
    season: str,
    _player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(InventoryService(db).catalog(season))


@router.post(
    "/add",
    response_model=Envelope[InventoryItemResponse],
    description="Development compatibility endpoint. Disabled outside dev/test.",
)
def add(
    payload: ItemRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(
        InventoryService(db).add_compatibility(player_id, payload), "Item added"
    )


@router.post("/remove", response_model=Envelope[InventoryItemResponse | None])
def remove(
    payload: ItemRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(InventoryService(db).remove(player_id, payload), "Item removed")


@router.post("/use", response_model=Envelope[InventoryItemResponse | None])
def use(
    payload: ItemRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(
        InventoryService(db).remove(player_id, payload, use=True), "Item used"
    )


@router.post("/transfer", response_model=Envelope[dict])
def transfer(
    payload: TransferRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(
        InventoryService(db).transfer(player_id, payload), "Item transferred"
    )
