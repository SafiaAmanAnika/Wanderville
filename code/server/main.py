from fastapi import FastAPI
from fastapi.exceptions import HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api.health import router as health_router
from app.api.auth import router as auth_router


app = FastAPI(title="Wanderville API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health_router)
app.include_router(auth_router)


@app.exception_handler(HTTPException)
async def http_exception_handler(_request, exc: HTTPException):
    # Keep errors consistent across the API.
    if isinstance(exc.detail, dict) and exc.detail.get("success") is False:
        return JSONResponse(status_code=exc.status_code, content=exc.detail)
    return JSONResponse(
        status_code=exc.status_code,
        content={"success": False, "error": "HTTP_ERROR", "message": str(exc.detail)},
    )
