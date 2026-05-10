# Wanderville

Wanderville is a 2.5D pixel-art isometric cozy social village game built with Godot and FastAPI.
The player can sign up, log in, enter a village world, move around, farm, use inventory, and later
meet friends in a shared community area.

## Repository Structure

`code/client/` - Godot client
`code/server/` - FastAPI backend
`doc/` - proposal, reports, references, and presentations

## Team Setup Guide

See `doc/setup/local_setup.md`.

## Run Server

```bash
cd code/server
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn main:app --reload
```

## Run Client

Open `code/client/project.godot` in Godot 4.6.
Press F5.

## Development Rule

Build a stable single-player-feeling foundation first.
Add WebSocket multiplayer after auth, player identity, movement, and map are stable.
