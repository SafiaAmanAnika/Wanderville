from sqlalchemy import Column, Integer, String, DateTime, Boolean, ForeignKey, and_
from sqlalchemy.orm import relationship
from datetime import datetime, timezone
from app.database import Base


class FarmPlot(Base):
    __tablename__ = "farm_plots"

    id = Column(Integer, primary_key=True, index=True)
    player_id = Column(Integer, ForeignKey("players.id", ondelete="CASCADE"), nullable=False, index=True)
    x = Column(Integer, nullable=False)
    y = Column(Integer, nullable=False)
    crop_type = Column(String(32), nullable=True)
    planted_at = Column(DateTime(timezone=True), nullable=True)
    growth_stage = Column(Integer, default=0)
    is_watered = Column(Boolean, default=False)
    is_harvested = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))

    GROWTH_TIMES = {
        "wheat": 60,
        "corn": 90,
        "cotton": 120,
        "tulip": 45,
        "paddy": 75,
    }

    MAX_STAGES = 3

    def time_to_next_stage(self) -> int:
        if not self.crop_type or self.crop_type not in self.GROWTH_TIMES:
            return 0
        total_time = self.GROWTH_TIMES[self.crop_type]
        return total_time // self.MAX_STAGES

    def can_advance(self) -> bool:
        if not self.planted_at or self.growth_stage >= self.MAX_STAGES:
            return False
        if not self.is_watered:
            return False
        elapsed = (datetime.now(timezone.utc) - self.planted_at).total_seconds()
        return elapsed >= self.time_to_next_stage() * (self.growth_stage + 1)

    def advance_if_ready(self) -> bool:
        if self.can_advance():
            self.growth_stage += 1
            self.is_watered = False
            return True
        return False

    def is_ready_for_harvest(self) -> bool:
        return self.growth_stage >= self.MAX_STAGES and not self.is_harvested

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "x": self.x,
            "y": self.y,
            "crop_type": self.crop_type,
            "growth_stage": self.growth_stage,
            "is_watered": self.is_watered,
            "is_harvested": self.is_harvested,
            "planted_at": self.planted_at.isoformat() if self.planted_at else None,
            "ready": self.is_ready_for_harvest(),
        }
