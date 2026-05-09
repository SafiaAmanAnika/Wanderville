from fastapi import APIRouter


router = APIRouter()


@router.get("/health")
def health() -> dict:
    return {"success": True, "data": {"status": "ok"}}
