import logging
import asyncio
import re
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from starlette.exceptions import HTTPException

from app.core.config import settings
from app.core.exceptions import AppError
from app.core.logging import configure_logging, request_logging
from app.core.responses import Envelope, ErrorResponse, success
from app.db import model_registry  # noqa: F401
from app.db.session import get_db
from app.modules.auth.router import router as auth_router
from app.modules.economy.router import router as economy_router
from app.modules.farming.router import router as farming_router
from app.modules.inventory.router import router as inventory_router
from app.modules.world.router import router as world_router
from app.modules.notifications.router import router as notifications_router
from app.modules.profile.router import router as profile_router
from app.modules.housing.router import router as housing_router
from app.modules.pets.router import router as pets_router
from app.modules.shop.router import router as shop_router
from app.modules.progression.router import router as progression_router
from app.modules.fishing.router import router as fishing_router
from app.modules.social.router import router as social_router
from app.modules.social.community_router import router as community_router
from app.modules.social.visit_router import router as farm_visit_router
from app.modules.realtime.router import router as realtime_router
from app.modules.realtime.native_voice import router as native_voice_router
from app.modules.realtime import policy_events  # noqa: F401
from app.modules.events.router import router as events_router
from app.modules.state.router import router as state_router


@asynccontextmanager
async def lifespan(_app):
    configure_logging()
    # Migrations and reference seeding are explicit commands, never startup work.
    logging.getLogger("wanderville").info(
        "Starting %s against %s, delivery=%s",
        settings.wanderville_env,
        settings.database_target,
        settings.email_delivery,
    )
    stop = asyncio.Event()
    task = asyncio.create_task(_world_worker(stop)) if settings.world_worker_enabled else None
    try:
        yield
    finally:
        stop.set()
        from app.modules.realtime.voice import voice_hub
        from app.modules.realtime.runtime import runtime
        await voice_hub.shutdown()
        runtime.clear()
        if task:
            await task


async def _world_worker(stop):
    """Optional single-service hobby deployment; no network keep-alive traffic."""
    from app.db.session import SessionLocal
    from app.modules.world.worker import tick

    cursor = 0
    def run_batch(after_id):
        with SessionLocal() as db:
            return tick(db, after_id=after_id)

    while not stop.is_set():
        try:
            cursor = await asyncio.to_thread(run_batch, cursor)
        except Exception as exc:
            logging.getLogger("wanderville").error(
                "World worker failed against %s: %s: %s",
                settings.database_target,
                type(exc).__name__,
                re.sub(r"://[^@\s]*@", "://***@", str(exc))[:300],
            )
            cursor = 0
        try:
            await asyncio.wait_for(stop.wait(), timeout=1 if cursor else 30)
        except TimeoutError:
            pass


def error(status, code, message):
    headers = {"WWW-Authenticate": "Bearer"} if status == 401 else None
    return JSONResponse(
        status_code=status,
        content=ErrorResponse(error=code, message=message).model_dump(),
        headers=headers,
    )


def create_app():
    app = FastAPI(title="WanderVille API", version="2.0.0", lifespan=lifespan)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.allowed_origins,
        allow_credentials=False,
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
        allow_headers=["Authorization", "Content-Type"],
    )
    app.middleware("http")(request_logging)

    @app.exception_handler(AppError)
    async def application_error(_request, exc):
        return error(exc.status, exc.code, exc.message)

    @app.exception_handler(RequestValidationError)
    async def validation_error(_request, exc):
        # Never echo exc.errors(): it includes raw passwords and tokens as input.
        return error(
            422,
            "VALIDATION_ERROR",
            "; ".join(
                f"{'.'.join(map(str, e['loc'][1:]))}: {e['msg']}" for e in exc.errors()
            ),
        )

    @app.exception_handler(HTTPException)
    async def http_error(_request, exc):
        return error(exc.status_code, "HTTP_ERROR", str(exc.detail))

    @app.exception_handler(IntegrityError)
    async def integrity_error(_request, _exc):
        return error(
            409, "DATA_CONFLICT", "This operation conflicts with existing data"
        )

    @app.exception_handler(SQLAlchemyError)
    async def database_error(_request, exc):
        # The type name alone cannot distinguish a bad host, bad credentials or a
        # missing schema, and none of these strings may carry the password.
        detail = re.sub(r"://[^@\s]*@", "://***@", str(getattr(exc, "orig", exc)))
        logging.getLogger("wanderville").error(
            "Database operation failed against %s: %s: %s",
            settings.database_target,
            type(exc).__name__,
            detail[:300],
        )
        return error(
            503, "DATABASE_UNAVAILABLE", "Database operation could not be completed"
        )

    @app.exception_handler(Exception)
    async def unexpected_error(_request, exc):
        logging.getLogger("wanderville").error(
            "Unhandled failure: %s", type(exc).__name__
        )
        return error(500, "INTERNAL_ERROR", "An unexpected error occurred")

    @app.get("/health", response_model=Envelope[dict], tags=["health"])
    def health():
        return success({"status": "ok"})

    @app.get("/ready", response_model=Envelope[dict], tags=["health"])
    def ready(db=Depends(get_db)):
        from sqlalchemy import text
        from app.core.exceptions import AppError

        db.execute(text("SELECT 1"))
        revision = db.scalar(text("SELECT version_num FROM alembic_version"))
        seeded = db.scalar(text("SELECT count(*) FROM item_definitions i JOIN item_rules r ON r.item_code = i.item_code WHERE i.item_code = 'wheat_seed'"))
        clock_ready = db.scalar(text("SELECT count(*) FROM world_state WHERE id = 1"))
        if revision != "0008_proximity_social" or not seeded or not clock_ready:
            raise AppError("DATABASE_NOT_READY", "Run database migrations and reference seeding", 503)
        return success({"status": "ready", "database": "connected"})

    for router in (
        auth_router,
        inventory_router,
        economy_router,
        world_router,
        farming_router,
        notifications_router,
        profile_router,
        housing_router,
        pets_router,
        shop_router,
        progression_router,
        fishing_router,
        community_router,
        social_router,
        farm_visit_router,
        events_router,
        realtime_router,
        native_voice_router,
        state_router,
    ):
        app.include_router(router)
    return app


app = create_app()
