from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.responses import Envelope, success
from app.db.session import get_db
from app.modules.auth.dependencies import get_current_player_id
from app.modules.farming.schemas import (
    FarmGridResponse,
    FarmTileResponse,
    HarvestResponse,
    PlantRequest,
    PlantResponse,
    PlotRequest,
    TileRequest,
)
from app.modules.farming.service import FarmingService

router = APIRouter(prefix="/farm", tags=["farming"])


@router.get("/plots", response_model=Envelope[FarmGridResponse])
def plots(
    player_id: int = Depends(get_current_player_id), db: Session = Depends(get_db)
):
    return success(FarmingService(db).list(player_id))


@router.post("/till", response_model=Envelope[FarmTileResponse])
def till(
    payload: TileRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(FarmingService(db).till(player_id, payload), "Tile tilled")


@router.post("/plant", response_model=Envelope[PlantResponse])
def plant(
    payload: PlantRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(FarmingService(db).plant(player_id, payload), "Crop planted")


@router.post("/water", response_model=Envelope[FarmTileResponse])
def water(
    payload: PlotRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(FarmingService(db).water(player_id, payload.plot_id), "Crop watered")


@router.post("/harvest", response_model=Envelope[HarvestResponse])
def harvest(
    payload: PlotRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(
        FarmingService(db).harvest(player_id, payload.plot_id), "Crop harvested"
    )


@router.post("/refill")
def refill(
    player_id: int = Depends(get_current_player_id), db: Session = Depends(get_db)
):
    return success(FarmingService(db).refill(player_id))
