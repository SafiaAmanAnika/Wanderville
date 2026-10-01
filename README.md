# WanderVille

A Godot village game with a FastAPI/PostgreSQL backend. The server supports
accounts, inventory, Aura/XP, farming, shop, fishing, housing, pets, social
interactions, progression, notifications, timed events and multiplayer APIs.
Godot integration remains a separate task.

## Documentation

- [Backend setup and upgrades](docs/BACKEND_UPDATE_GUIDE.md)
- [Database configuration](docs/DATABASE_SETUP.md)
- [Backend architecture](docs/BACKEND_STRUCTURE.md)
- [Existing Godot API contracts](docs/API_CONTRACT.md)
- [New gameplay and WebSocket APIs](docs/NEW_API_REFERENCE.md)
- [Schema](docs/database/SCHEMA.md) and [ERD](docs/database/ERD.md)
- [Requirements coverage](docs/SRS_BACKEND_AUDIT.md)
- [Verification results](docs/VERIFICATION_RESULTS.md)
- [Remaining Godot integration](docs/BACKEND_INTEGRATION_CHECKLIST.md)

## Run the backend

Use Python 3.12. Configure a PostgreSQL database and random JWT secret in
`code/server/.env`; see `.env.example` for settings. Preserve existing databases
and use the additive Alembic migration chain for upgrades.

```powershell
cd code/server
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements-dev.txt
# For a new setup only: copy .env.example to .env and configure it.
python -m alembic upgrade head
python -m app.db.seed
python -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

In a second terminal using the same environment:

```powershell
cd code/server
.\.venv\Scripts\Activate.ps1
python -m app.modules.world.worker
```

Migrations and reference seeding are explicit. API startup never resets a database.
Development account emails use the local `.dev-mail/` mailbox. Open `/docs` for
interactive API documentation. Arbitrary inventory/currency awards are available
only in development/test environments.

## Test the backend

From `code/server`:

```powershell
python -m pytest -q
python -m ruff check app migrations tests scripts
python -m compileall -q app migrations tests scripts
```

SQLite tests run by default. Real PostgreSQL concurrency tests require an explicitly
disposable `*_test` database with `WANDERVILLE_TEST_DATABASE_URL` and
`WANDERVILLE_ALLOW_TEST_RESET=1`; never use a live database for these tests.
See the verification report for exact commands, counts and live-process evidence.

## Run the client

Open `code/client/project.godot` in Godot and run the project. Existing local
farming, inventory, session and UI flows still need the mappings documented in the
integration checklist. Backend support alone does not complete those Godot features.
