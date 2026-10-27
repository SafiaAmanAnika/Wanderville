"""Application composition.

Nothing here contains behaviour. This module wires the middleware, the
exception translators and the routers together, and supervises the one
long-running background task. Each concern lives in the module named after it:

``app.core.errors``       exception -> HTTP status
``app.health.router``     liveness and readiness probes
``app.core.logging``      request logging
``app.modules.world.worker`` the growth/visit sweep itself
"""

import asyncio
import logging
import re
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core import errors
from app.core.config import settings
from app.core.logging import configure_logging, request_logging
from app.db import model_registry  # noqa: F401
from app.db.session import SessionLocal
from app.health.router import router as health_router
from app.modules.auth.router import router as auth_router
from app.modules.economy.router import router as economy_router
from app.modules.events.router import router as events_router
from app.modules.farming.router import router as farming_router
from app.modules.fishing.router import router as fishing_router
from app.modules.housing.router import router as housing_router
from app.modules.inventory.router import router as inventory_router
from app.modules.market.router import router as market_router
from app.modules.notifications.router import router as notifications_router
from app.modules.pets.router import router as pets_router
from app.modules.progression.router import router as progression_router
from app.modules.profile.router import router as profile_router
from app.modules.realtime.native_voice import router as native_voice_router
from app.modules.realtime.policy_events import register as register_policy_events
from app.modules.realtime import position_projection
from app.modules.realtime.admission_router import router as multiplayer_admission_router
from app.modules.realtime.internal_router import router as internal_multiplayer_router
from app.modules.realtime.router import router as realtime_router
from app.modules.realtime.runtime import runtime
from app.modules.realtime.voice import voice_hub
from app.modules.shop.router import router as shop_router
from app.modules.social.community_router import router as community_router
from app.modules.social.router import router as social_router
from app.modules.social.visit_router import router as farm_visit_router
from app.modules.state.router import router as state_router
from app.modules.trees.router import router as trees_router
from app.modules.world.router import router as world_router

# The authoritative record of the API surface, grouped by area.
ROUTERS = (
    health_router,
    # identity
    auth_router,
    # gameplay
    inventory_router,
    economy_router,
    world_router,
    farming_router,
    fishing_router,
    trees_router,
    shop_router,
    progression_router,
    housing_router,
    pets_router,
    # social
    social_router,
    community_router,
    farm_visit_router,
    notifications_router,
    profile_router,
    # realtime
    realtime_router,
    native_voice_router,
    # multiplayer admission: public ticket issue, private host consumption
    multiplayer_admission_router,
    internal_multiplayer_router,
    events_router,
    # composite
    state_router,
    #market
    shop_router,
    market_router, 
)

# Bounds how much of a database error may reach the logs.
MAX_LOGGED_DETAIL = 300
# Cadence of the background sweep: 1s while there is work left to hand out,
# otherwise 30s, so an idle server is not waking up constantly.
ACTIVE_WORKER_INTERVAL = 1
IDLE_WORKER_INTERVAL = 30


async def _world_worker(stop):
    """Optional single-service hobby deployment; no network keep-alive traffic."""
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
                re.sub(r"://[^@\s]*@", "://***@", str(exc))[:MAX_LOGGED_DETAIL],
            )
            cursor = 0
        try:
            await asyncio.wait_for(
                stop.wait(),
                timeout=ACTIVE_WORKER_INTERVAL if cursor else IDLE_WORKER_INTERVAL,
            )
        except TimeoutError:
            pass


@asynccontextmanager
async def lifespan(_app):
    configure_logging()
    # Migrations and reference seeding are explicit commands, never startup work.
    logging.getLogger("wanderville").info(
        "Starting %s against %s, delivery=%s, presence=%s",
        settings.wanderville_env,
        settings.database_target,
        settings.email_delivery,
        settings.presence_backend,
    )
    # Apply the configured bounds before the first socket can record a position.
    position_projection.configure(
        max_players=settings.presence_memory_max_players,
        ttl_seconds=settings.presence_memory_ttl_seconds,
    )
    stop = asyncio.Event()
    task = asyncio.create_task(_world_worker(stop)) if settings.world_worker_enabled else None
    try:
        yield
    finally:
        stop.set()
        await voice_hub.shutdown()
        runtime.clear()
        position_projection.reset()
        if task:
            await task


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
    errors.register(app)
    # Revoke realtime permissions when a policy row commits. Explicit, so the
    # dependency is visible here rather than being an import side effect.
    register_policy_events()
    for router in ROUTERS:
        app.include_router(router)
    return app


app = create_app()