# Backend Setup Documentation

This directory contains guides for setting up and testing the Wanderville backend.

## Guides

| File | Purpose |
|---|---|
| `local_setup.md` | Step-by-step local environment setup (Python, venv, dependencies, database, migrations, server) |
| `manual_backend_test_guide.md` | Manual testing instructions with curl commands for all auth endpoints, OAuth2 verification, and database checks |

## Quick Start (for experienced developers)

```bash
cd code/server
python -m venv .venv
source .venv/Scripts/activate
pip install -r requirements.txt
cp .env.example .env
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
│   │   └── world.py         # /world/me, /world/tiles, /world/tile
│   ├── deps/                # FastAPI dependencies
│   │   └── auth.py          # get_current_player, get_current_player_id, check_owner
│   ├── models/              # SQLAlchemy models
│   │   ├── player.py        # Player table
│   │   └── world.py         # World table (map data)
│   ├── schemas/             # Pydantic request/response schemas
│   │   ├── auth.py          # SignupRequest, LoginRequest
│   │   ├── player.py        # PlayerPublic
│   │   └── world.py         # WorldCreate, WorldPublic, TileUpdate
│   ├── services/            # Business logic
│   │   ├── auth_service.py  # signup, login, JWT helpers
│   │   └── world_service.py # get_world_by_owner, create_world, update_tiles
│   ├── websocket/           # (future: multiplayer sync)
│   └── scheduler/           # (future: crop growth ticks)
├── migrations/              # Alembic migration files
│   ├── env.py
│   └── versions/            # Generated migration scripts
└── tests/                   # pytest tests
    ├── test_auth.py
    └── test_auth_deps.py
```

## For Backend Developers

- Read `local_setup.md` for the full setup process.
- Read `manual_backend_test_guide.md` for testing instructions.
- Always run `python -m alembic upgrade head` after pulling changes that include new migrations.
- Never commit `.env`, `.venv/`, `wanderville.db`, or test database files.
