# Backend Setup Documentation

This directory contains guides for setting up and testing the Wanderville backend.

## Guides

| File | Purpose |
|---|---|---|
| `local_setup.md` | Step-by-step local environment setup (Python, venv, dependencies, database, migrations, server) |
| `manual_backend_test_guide.md` | Manual testing instructions with curl commands for auth, world, farm, and inventory endpoints |

## Quick Start (for experienced developers)

```powershell
cd code/server
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
Copy-Item .env.example .env
python -m alembic upgrade head
python -m pytest -q
uvicorn main:app --reload
```

## Key Technologies

- **FastAPI** 0.115.0 — web framework
- **SQLAlchemy** 2.0.36 — ORM (synchronous)
- **SQLite** — local database
- **Alembic** 1.13.1 — database migrations
- **python-jose** — JWT encoding/decoding
- **passlib + bcrypt** — password hashing
- **pytest** + **httpx** — testing
- **OAuth2PasswordBearer** — token-based auth with auto-generated OpenAPI docs

## Project Structure

```
code/server/
├── main.py                  # FastAPI app entry point
├── alembic.ini              # Alembic configuration
├── requirements.txt         # Python dependencies
├── app/
│   ├── config.py            # Pydantic settings (loads .env)
│   ├── database.py          # SQLAlchemy engine + session
│   ├── api/                 # Route handlers
│   │   ├── auth.py          # /auth/signup, /auth/login, /auth/me
│   │   ├── health.py        # /health
│   │   ├── world.py         # /world/me, /world/tiles, /world/tile
│   │   ├── farm.py          # /farm/plots, /farm/plant, /farm/water, /farm/harvest
│   │   └── inventory.py     # /inventory/, /inventory/add, /inventory/remove, /inventory/transfer
│   ├── deps/                # FastAPI dependencies
│   │   ├── auth.py          # get_current_player, get_current_player_id, check_owner
│   │   └── rate_limit.py    # In-memory sliding-window rate limiter
│   ├── models/              # SQLAlchemy models
│   │   ├── player.py        # Player table (id, username, hashed_password, display_name, created_at, is_active, position_x, position_y)
│   │   ├── world.py         # World table (map data with JSON tiles dict)
│   │   ├── farm.py          # FarmPlot table (crop type, growth stage, watering, harvesting)
│   │   └── inventory.py     # InventoryItem table (item_type, quantity, slot_index)
│   ├── schemas/             # Pydantic request/response schemas
│   │   ├── auth.py          # SignupRequest, LoginRequest
│   │   ├── player.py        # PlayerPublic
│   │   ├── world.py         # WorldPublic, TileUpdate, TilesBulkUpdate
│   │   ├── farm.py          # PlantRequest, WaterRequest, HarvestRequest, FarmGridResponse, etc.
│   │   ├── inventory.py     # AddItemRequest, RemoveItemRequest, TransferItemRequest, etc.
│   │   └── responses.py     # Generic Envelope[T] + typed response aliases
│   ├── services/            # Business logic
│   │   ├── auth_service.py  # signup, login, JWT helpers
│   │   ├── world_service.py # get_world_by_owner, create_world, update_tiles
│   │   ├── farm_service.py  # plant_crop, water_crop, harvest_crop, tick_growth
│   │   └── inventory_service.py # add_item, remove_item, transfer_item, has_item
│   ├── websocket/           # (future: multiplayer sync)
│   └── scheduler/           # (future: crop growth ticks)
├── migrations/              # Alembic migration files
│   ├── env.py
│   └── versions/            # Generated migration scripts
└── tests/                   # pytest tests (41 tests total)
    ├── test_auth.py
    ├── test_auth_deps.py
    ├── test_world.py
    ├── test_world_service.py
    └── test_inventory.py
```

## For Backend Developers

- Read `local_setup.md` for the full setup process.
- Read `manual_backend_test_guide.md` for testing instructions (auth, world, farm, inventory).
- Always run `python -m alembic upgrade head` after pulling changes that include new migrations.
- Never commit `.env`, `.venv/`, `wanderville.db`, or test database files.
