# Build and run

Practical local commands and the deployment configuration present in this repository.

<details>
<summary><strong>Explore this page</strong></summary>

[Home](../README.md) · [Requirements](#requirements) · [Existing Windows launchers](#existing-windows-launchers) · [Existing database setup](#existing-database-setup) · [Deployment and export](#deployment-and-export) · [Recovery](#recovery)

</details>


## Requirements

Python **3.12.12** is pinned in both `.python-version` files. The Godot project targets **4.6**. PostgreSQL is the production persistence engine. Server dependencies are pinned in [requirements.txt](../code/server/requirements.txt); test dependencies live in [requirements-dev.txt](../code/server/requirements-dev.txt).

## Existing Windows launchers

The checked-in launchers expect `code/server/.venv312`. Set `GODOT_EXE` to your actual Godot executable path. Start the server before the game.

```powershell
# From the repository root; installs into this checkout's environment.
py -3.12 -m venv code/server/.venv312
.\code\server\.venv312\Scripts\python.exe -m pip install -r code/server/requirements.txt
# Inspect local_development.py before its first run: it provisions local dev state.
.\code\server\.venv312\Scripts\python.exe code/server/scripts/local_development.py --serve
```

In a second terminal, after setting `GODOT_EXE`:

```powershell
.\Start-Local-Game.cmd
```

`Start-Local-Server.cmd` uses `--lan`; omit `--lan` as in the explicit command above for this machine alone. The game launcher checks `http://127.0.0.1:8000/ready` before starting Godot and sets its API URL to that local service. Read [local_development.py](../code/server/scripts/local_development.py) for PostgreSQL discovery and provisioning prerequisites. These commands were source-reviewed, not executed against your database in this pass.

## Existing database setup

Copy `.env.example` to an untracked `code/server/.env` and fill in a dedicated database URL, JWT secret and delivery settings. Do not overwrite an existing `.env`. Configuration is defined in [config.py](../code/server/app/core/config.py).

From `code/server`, with that environment configured:

```powershell
.\.venv312\Scripts\python.exe -m alembic upgrade head
.\.venv312\Scripts\python.exe -m app.db.seed
.\.venv312\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --workers 1
```

Migrations and seeds change the configured database. Back up real player data first. `/health` is liveness; `/ready` checks readiness. A successful health response alone does not establish that migrations or reference data are ready.

## Deployment and export

[render.yaml](../render.yaml) describes a Python service rooted at `code/server`, with dependency installation followed by migration, seed and one-worker Uvicorn startup. It references an externally configured PostgreSQL database. It is a deployment blueprint, not evidence of a live service or current free-tier terms.

The blueprint disables the world worker and voice. It installs `requirements.txt`, not optional voice dependencies. Email uses configured Gmail API sender credentials; Google sign-in credentials are separate. Set secrets through the deployment environment. Never put database credentials into a game export.

Open [project.godot](../code/client/project.godot) in the matching Godot version, configure the API endpoint for your target, and create an export preset for the platform. No universal release binary is linked because an export was not built or tested in this pass. The checked-in project endpoint is not asserted to be available.

The game export needs its activity scenes and dynamically loaded assets as well as the campus: six house interiors and floor layers, furniture manifest/directional textures, fishing/target/species resources, pet animations, character presets, marketplace placement data and the sound catalog. Verify those resources in the exported build, including title/world/marketplace/fishing music and both volume buses; a successful backend startup does not exercise them. House layouts, audio preferences and other device-local saves live in Godot's user-data directory and are not PostgreSQL backups.

## Recovery

Keep a database backup and matching code revision before release. Restore into a separate database and verify readiness plus core actions before switching traffic. Reverting code alone does not reverse a schema change. See [database](DATABASE.md) and [testing](TESTING.md).

<details>
<summary><strong>Source and verification</strong></summary>

Source reviewed: `31ca97c39c05` · 2026-11-01. Source inspection is not a new gameplay test.

</details>

[← Previous](TESTING.md) · [Back to top](#build-and-run) · [Next →](CREATORS_NOTE.md)
