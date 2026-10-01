# WanderVille

A Godot desktop village game with a FastAPI/PostgreSQL backend. The backend now
uses domain modules for authentication, players, inventory, economy, worlds, and
farming. The supplied Godot client is unchanged.

## Start here

- [Backend setup and run commands](docs/DATABASE_SETUP.md)
- [Manual backend checks](docs/MANUAL_BACKEND_TEST_GUIDE.md)
- [Implementation report and final folder tree](docs/IMPLEMENTATION_REPORT.md)
- [OpenCode review](docs/OPENCODE_REVIEW.md) and [run/fix prompt](docs/OPENCODE_RUN_FIX_PROMPT.md)
- [Backend architecture](docs/BACKEND_STRUCTURE.md)
- [Godot API contract](docs/API_CONTRACT.md)
- [Remaining client integration work](docs/BACKEND_CLIENT_INTEGRATION_GAPS.md)
- [Database schema](docs/database/SCHEMA.md) and [ERD](docs/database/ERD.md)
- [Development database reset](docs/database/RESET.md)

## Run the backend

Use Python 3.12 and a **fresh** PostgreSQL database. The old development migration
chain was intentionally replaced by `0001_initial_schema`.

```powershell
cd code/server
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements-dev.txt
if (!(Test-Path .env)) { Copy-Item .env.example .env }
# Edit .env with your new local database connection and a random JWT secret.
python -m alembic upgrade head
python -m app.db.seed
python -m pytest -q
python -m uvicorn main:app --reload --no-access-log
```

Migrations and seeding are explicit; startup never creates or resets a schema.
Development verification emails are in `code/server/.dev-mail/`, not server logs.
Open `/docs` to exercise the API. New inventories start empty; the local-only
`/inventory/add` endpoint can supply seeds for manual development tests.

## Run the client

Open `code/client/project.godot` in Godot 4.6 and press F5. Farming actions,
water, and farm reconstruction still need the future integration described in
the gap document. Backend persistence does not automatically persist local Godot
actions.

## Applying this deliverable to an existing checkout

Extract this archive into a separate directory first. Preserve your current
`.env` and local virtual environment. Replace the backend source, migration and
test directories as a set; simply overlaying files would leave deleted legacy
modules behind. Copy the new docs/README as needed. Keep your existing
`code/client/` directory untouched. No Git checkout/reset/clean is required.
Documentation now lives entirely in `docs/`; the former `doc/setup/` guides have
been merged there. Remove those obsolete guides when applying this update,
preserving any other documentation you added locally.
The archive includes an identical copy of the uploaded client but excludes Git
metadata, local Python environments, credentials, mail tokens and test caches.
