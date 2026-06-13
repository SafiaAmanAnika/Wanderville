from sqlalchemy.orm import Session
from sqlalchemy import and_
from datetime import datetime, timezone
from app.models.farm import FarmPlot
from app.models.player import Player


class FarmError(Exception):
    pass


class NotEnoughWater(FarmError):
    pass


class PlotNotFound(FarmError):
    pass


class PlotNotReady(FarmError):
    pass


class PlotAlreadyHarvested(FarmError):
    pass


class PlotOccupied(FarmError):
    pass


class InvalidCrop(FarmError):
    pass


WATER_COST_PLANT = 5
WATER_COST_WATER = 2


def get_farm_grid(db: Session, player_id: int) -> list[FarmPlot]:
    return db.query(FarmPlot).filter(
        and_(
            FarmPlot.player_id == player_id,
            FarmPlot.is_harvested == False
        )
    ).all()


def plant_crop(db: Session, player_id: int, x: int, y: int, crop_type: str) -> FarmPlot:
    existing = db.query(FarmPlot).filter(
        and_(
            FarmPlot.player_id == player_id,
            FarmPlot.x == x,
            FarmPlot.y == y,
            FarmPlot.is_harvested == False
        )
    ).first()
    if existing:
        raise PlotOccupied(f"Plot at ({x}, {y}) is already occupied")

    if crop_type not in FarmPlot.GROWTH_TIMES:
        raise InvalidCrop(f"Unknown crop type: {crop_type}. Valid: {list(FarmPlot.GROWTH_TIMES.keys())}")

    plot = FarmPlot(
        player_id=player_id,
        x=x,
        y=y,
        crop_type=crop_type,
        planted_at=datetime.now(timezone.utc),
        growth_stage=0,
        is_watered=False,
    )
    db.add(plot)
    db.commit()
    db.refresh(plot)
    return plot


def water_crop(db: Session, player_id: int, plot_id: int) -> FarmPlot:
    plot = db.query(FarmPlot).filter(
        and_(FarmPlot.id == plot_id, FarmPlot.player_id == player_id)
    ).first()
    if not plot:
        raise PlotNotFound(f"Plot {plot_id} not found or does not belong to you")
    if plot.is_harvested:
        raise PlotAlreadyHarvested(f"Plot {plot_id} has already been harvested")
    if plot.is_watered:
        raise FarmError(f"Plot {plot_id} is already watered")

    plot.is_watered = True
    plot.advance_if_ready()
    db.commit()
    db.refresh(plot)
    return plot


def harvest_crop(db: Session, player_id: int, plot_id: int) -> tuple[FarmPlot, str, int]:
    plot = db.query(FarmPlot).filter(
        and_(FarmPlot.id == plot_id, FarmPlot.player_id == player_id)
    ).first()
    if not plot:
        raise PlotNotFound(f"Plot {plot_id} not found or does not belong to you")
    if not plot.is_ready_for_harvest():
        raise PlotNotReady(f"Plot {plot_id} is not ready for harvest (stage {plot.growth_stage}/{plot.MAX_STAGES})")

    crop_type = plot.crop_type
    plot.is_harvested = True
    db.commit()
    db.refresh(plot)
    return plot, crop_type, 1


def tick_growth(db: Session, player_id: int) -> list[FarmPlot]:
    plots = db.query(FarmPlot).filter(
        and_(
            FarmPlot.player_id == player_id,
            FarmPlot.is_watered == True,
            FarmPlot.is_harvested == False
        )
    ).all()
    advanced = []
    for plot in plots:
        if plot.advance_if_ready():
            advanced.append(plot)
    if advanced:
        db.commit()
    return advanced
