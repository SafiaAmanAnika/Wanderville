from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.database import get_db
from app.deps.auth import get_current_player_id
from app.schemas.farm import (
    PlantRequest, WaterRequest, HarvestRequest,
    FarmGridResponse, FarmPlotResponse, PlantResponseData, HarvestResponseData
)
from app.schemas.responses import Envelope
from app.services import farm_service

router = APIRouter(prefix="/farm", tags=["farm"])


@router.get("/plots", response_model=Envelope[FarmGridResponse])
def get_farm_plots(
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db)
):
    plots = farm_service.get_farm_grid(db, player_id)
    return Envelope(
        success=True,
        data={"plots": [p.to_dict() for p in plots], "player_id": player_id},
        message="Farm plots retrieved"
    )


@router.post("/plant", response_model=Envelope[PlantResponseData])
def plant(
    req: PlantRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db)
):
    try:
        plot = farm_service.plant_crop(db, player_id, req.x, req.y, req.crop_type)
        return Envelope(
            success=True,
            data={"plot": plot.to_dict(), "water_remaining": 50},
            message=f"{req.crop_type} planted at ({req.x}, {req.y})"
        )
    except farm_service.FarmError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/water", response_model=Envelope[FarmPlotResponse])
def water(
    req: WaterRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db)
):
    try:
        plot = farm_service.water_crop(db, player_id, req.plot_id)
        return Envelope(
            success=True,
            data=plot.to_dict(),
            message=f"Plot {req.plot_id} watered"
        )
    except farm_service.FarmError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/harvest", response_model=Envelope[HarvestResponseData])
def harvest(
    req: HarvestRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db)
):
    try:
        plot, crop_type, quantity = farm_service.harvest_crop(db, player_id, req.plot_id)
        return Envelope(
            success=True,
            data={"plot": plot.to_dict(), "crop_type": crop_type, "quantity": quantity},
            message=f"Harvested {quantity} {crop_type}"
        )
    except farm_service.FarmError as e:
        raise HTTPException(status_code=400, detail=str(e))
