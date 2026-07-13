import logging
import time
from pathlib import Path
from urllib.parse import urlparse

from alembic import command
from alembic.config import Config

from fastapi import FastAPI, Request
from fastapi.exceptions import HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api.health import router as health_router
from app.api.auth import router as auth_router
from app.api.world import router as world_router
from app.api.farm import router as farm_router
from app.api.inventory import router as inventory_router
from app.api.economy import router as economy_router
from app.config import settings
from app.database import Base, engine

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
)

logger = logging.getLogger("wanderville")

app = FastAPI(title="Wanderville API")


def upgrade_database_schema() -> None:
    parsed_url = urlparse(settings.database_url)
    if parsed_url.scheme.startswith("sqlite"):
        logger.info("Skipping automatic Alembic upgrade for SQLite database.")
        return

    if not parsed_url.scheme.startswith("postgresql"):
        logger.warning(
            "DATABASE_URL is not set to PostgreSQL/Neon. Skipping automatic migration startup."
        )
        return

    alembic_ini = Path(__file__).resolve().parent / "alembic.ini"
    alembic_cfg = Config(str(alembic_ini))
    alembic_cfg.set_main_option("script_location", str(alembic_ini.parent / "migrations"))
    logger.info("Running Alembic upgrade head against configured database.")
    command.upgrade(alembic_cfg, "head")

cors_origins = (
    ["*"]
    if settings.cors_origins == "*"
    else [o.strip() for o in settings.cors_origins.split(",")]
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def startup_tasks() -> None:
    upgrade_database_schema()


@app.middleware("http")
async def request_logging_middleware(request: Request, call_next):
    start = time.perf_counter()
    response = await call_next(request)
    duration = time.perf_counter() - start
    logger.info(
        "%s %s %d %.3fs",
        request.method,
        request.url.path,
        response.status_code,
        duration,
    )
    return response


app.include_router(health_router)
app.include_router(auth_router)
app.include_router(world_router)
app.include_router(farm_router)
app.include_router(inventory_router)
app.include_router(economy_router)


@app.exception_handler(HTTPException)
async def http_exception_handler(_request, exc: HTTPException):
    if isinstance(exc.detail, dict) and exc.detail.get("success") is False:
        return JSONResponse(status_code=exc.status_code, content=exc.detail)
    return JSONResponse(
        status_code=exc.status_code,
        content={"success": False, "error": "HTTP_ERROR", "message": str(exc.detail)},
    )