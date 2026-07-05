# Wanderville

Wanderville is a 2D pixel-art isometric cozy social village game built with Godot and FastAPI.
The player can sign up, log in, enter a village world, move around, farm, use inventory, and later
meet friends in a shared community area.

## Repository Structure

`code/client/` - Godot client
`code/server/` - FastAPI backend
`doc/` - proposal, reports, references, and presentations

## Team Setup Guide

See `doc/setup/local_setup.md`.

## Prerequisites

- Python 3.10+
- PostgreSQL 14+ (local or [Neon](https://neon.tech) cloud)
- Godot 4.6

## Database Setup

Set up a PostgreSQL database and create the `.env` file:

```powershell
cd code/server
Copy-Item .env.example .env
# Edit .env → set DATABASE_URL to your PostgreSQL connection string
```

Example `DATABASE_URL`:
```
DATABASE_URL=postgresql://user:password@localhost:5432/wanderville
```

## Run Server

```powershell
cd code/server
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python -m alembic upgrade head   # apply migrations
uvicorn main:app --reload
```

> The first run also auto-creates tables via `Base.metadata.create_all()` as a fallback, but running `alembic upgrade head` is the recommended approach.

## Run Client

Open `code/client/project.godot` in Godot 4.6.
Press F5.

## Development Rule

Build a stable single-player-feeling foundation first.
Add WebSocket multiplayer after auth, player identity, movement, and map are stable.
