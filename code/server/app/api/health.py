from fastapi import APIRouter

from app.schemas.responses import HealthData, HealthResponse

router = APIRouter()


@router.get("/health", response_model=HealthResponse)
def health() -> dict:
    """Return the health status of the API."""
    return {"success": True, "data": {"status": "ok"}}
