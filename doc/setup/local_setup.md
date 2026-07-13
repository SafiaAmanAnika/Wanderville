# Local Setup (Beginner Guide)

This guide explains how to set up Wanderville on your machine for local development.

## Required Tools

- Git + Git Bash (Windows)
- Python (3.10+ recommended)
- Godot 4.x
- VS Code (or any editor)

Verify installs (optional):

```bash
git --version
python --version
```

## Clone The Repo

```bash
git clone https://github.com/SafiaAmanAnika/Wanderville.git
cd Wanderville
```

## Backend Setup

From the repo root, run:

```powershell
cd code/server
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
cp .env.example .env
# Edit .env → set DATABASE_URL to your PostgreSQL connection string
python -m alembic upgrade head   # apply database migrations
python -m pytest -q              # run tests
uvicorn main:app --reload
```

Notes:

- Keep the terminal running while `uvicorn` is running.
- If activation fails on your machine, see Troubleshooting.
- Migrations are managed with Alembic. Always run `python -m alembic upgrade head` after pulling.
- Set `$env:DISABLE_RATE_LIMIT=1` to disable the in-memory rate limiter during development.
- Tests use isolated SQLite files automatically — no PostgreSQL needed for tests.
- If Alembic says `Context impl SQLiteImpl` and then fails with `table item_definitions already exists`, you are on a stale SQLite database, not PostgreSQL. Delete the local `*.db` file for that environment or reset the migration history before rerunning `python -m alembic upgrade head`.
- Do not keep an old SQLite database around when switching branches or rerunning migrations, because the app also creates tables on startup and that can leave Alembic and the actual schema out of sync.

## PostgreSQL Setup, Step By Step

Use PostgreSQL for the actual running game server. The backend reads its database settings from `code/server/.env`, so if you point `DATABASE_URL` at Neon, the API, Alembic, and any friend using the same backend will all use that same shared database.

### 1. Install PostgreSQL

- Install PostgreSQL 14+ on Windows, or use a managed provider like Neon.
- Make sure the PostgreSQL service is running.
- Confirm the client tools are available by running `psql --version`.

### 2. Create A Database And User

Open `psql` as a PostgreSQL superuser and create a dedicated database and role:

```sql
CREATE DATABASE wanderville;
CREATE USER wanderville_admin WITH PASSWORD 'choose-a-strong-password';
GRANT ALL PRIVILEGES ON DATABASE wanderville TO wanderville_admin;
```

If you are using Neon or another hosted database, skip this step and use the database and username they provide.

### 3. Create The Local `.env`

Copy the example file and edit it:

```powershell
Copy-Item .env.example .env
```

Make sure `code/server/.env` contains values like these:

```env
WANDEVILLE_ENV=dev
WANDEVILLE_HOST=127.0.0.1
WANDEVILLE_PORT=8000
DATABASE_URL=postgresql+psycopg2://wanderville_admin:your-password@localhost:5432/wanderville
JWT_SECRET_KEY=some-long-random-value
ACCESS_TOKEN_EXPIRE_MINUTES=10080
CORS_ORIGINS=http://localhost:8080,http://127.0.0.1:8080
```

Use `postgresql+psycopg2://...` because the server installs `psycopg2-binary`.

If you use a hosted database, your URL may also need `?sslmode=require` at the end.

### 4. Verify The Connection

Before running migrations, confirm PostgreSQL accepts the credentials:

```powershell
psql "postgresql://wanderville_admin:your-password@localhost:5432/wanderville" -c "SELECT 1"
```

If that fails, fix the database, username, password, or port before continuing.

### 5. Apply Migrations

From `code/server`, run:

```powershell
python -m alembic upgrade head
```

This creates the schema in PostgreSQL and records the current migration state.

### 6. Start The Server

```powershell
uvicorn main:app --reload
```

If the server starts cleanly, open `http://127.0.0.1:8000/docs` to verify the API is responding.

## Database

The project uses **PostgreSQL** via **SQLAlchemy** + **Alembic** for migrations.

Create a PostgreSQL database (local or [Neon](https://neon.tech) cloud):

```sql
CREATE DATABASE wanderville;
CREATE USER wanderville_admin WITH PASSWORD 'wanderville123';
GRANT ALL PRIVILEGES ON DATABASE wanderville TO wanderville_admin;
```

Then configure `DATABASE_URL` in `code/server/.env`:
```
DATABASE_URL=postgresql+psycopg2://USER:PASSWORD@HOST/wanderville?sslmode=require
```

Apply migrations:
```powershell
cd code/server
.\.venv\Scripts\Activate.ps1
python -m alembic upgrade head
```

### Resetting the database

```powershell
# Drop and recreate (PostgreSQL)
psql -U wanderville_admin -d wanderville -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"
python -m alembic upgrade head
```

## Files/Folders You Must Not Commit

These are local-only artifacts and should never be pushed to GitHub:

- `.env`
- `.venv/`
- `test_*.db` (test SQLite databases, e.g. `test_auth.db`, `test_world.db`, `test_inventory.db`)
- `wanderville.db` (only if you ever run with SQLite locally)
- `__pycache__/`
- `.pytest_cache/`
- `.godot/`
- `.import/`

If you accidentally created/edited any of these, remove them from staging before committing.

## Testing the Full Flow (What Works)

After setup, verify everything works end-to-end:

### 1. Start the backend

```powershell
cd code/server
.\.venv\Scripts\Activate.ps1
uvicorn main:app --reload
```

### 2. Start the Godot client

1. Open Godot 4.
2. Import `code/client/project.godot`.
3. Press **F5** (Play).

### 3. Sign up / Log in

- The game opens to a login screen.
- Click **Sign Up**, enter a username, password, and display name.
- After signup you're logged in automatically.
- On subsequent launches, if you checked "Remember this device", you'll skip login.

### 4. Character Selection

- After login you land on the **Character Select** screen.
- **Female Farmer** is the only unlocked character. Her sprite shows as a portrait.
- The other slots (Male Farmer, Explorer, Mage) are locked/grayed — they have no assets yet.
- Click the Female Farmer card → gold border confirms selection.
- Click **Confirm** to proceed.

### 5. Map / World Selection

- The **Map Selection** screen shows your world(s) as styled cards.
- Currently each player gets one auto-created world (named "My World").
- Hover a card → blue border. Click → gold flash, then the world loads.

### 6. In the World

- Your character spawns at the spawn point `(7377, -891)` with the girl sprite.
- **WASD / Arrow keys** to move.
- **E** to open the seed picker (when near your farm area).
- Walk up to a SignBoard to see info.
- Press **ESC** or click the menu button to open settings (music/SFX volume, remember device toggle).

### 7. Settings

- Click **Settings** on the Map Selection screen.
- Adjust Music / SFX volume sliders.
- Toggle "Remember this device" — saves to config, auto-login on next launch.
- Click **Close** to dismiss.

### 8. API Testing (Quick Checks)

With the backend running at `http://127.0.0.1:8000`:

**Auth**
```powershell
# Health check
curl http://127.0.0.1:8000/health

# Sign up a test user
curl -X POST http://127.0.0.1:8000/auth/signup `
  -H "Content-Type: application/json" `
  -d '{"username":"testuser","password":"secret123","display_name":"Test User"}'

# Log in (save the token)
curl -X POST http://127.0.0.1:8000/auth/login `
  -H "Content-Type: application/json" `
  -d '{"username":"testuser","password":"secret123"}'

# Get profile (replace TOKEN with your JWT)
curl http://127.0.0.1:8000/auth/me -H "Authorization: Bearer TOKEN"
```

**World**
```powershell
# Get or create your personal world
curl http://127.0.0.1:8000/world/me -H "Authorization: Bearer TOKEN"

# Get global world state
curl http://127.0.0.1:8000/world/state -H "Authorization: Bearer TOKEN"
```

**Inventory & Economy**
```powershell
curl http://127.0.0.1:8000/inventory/ -H "Authorization: Bearer TOKEN"
curl http://127.0.0.1:8000/economy/ -H "Authorization: Bearer TOKEN"
curl http://127.0.0.1:8000/inventory/catalog -H "Authorization: Bearer TOKEN"
```

**Farming**
```powershell
curl http://127.0.0.1:8000/farm/plots -H "Authorization: Bearer TOKEN"
```

You can also use the autogenerated Swagger docs at `http://127.0.0.1:8000/docs`.

### 9. Running Tests

```powershell
cd code/server
.\.venv\Scripts\Activate.ps1
pytest -q
```

The test suite uses **isolated SQLite files** (`test_*.db`) automatically — no PostgreSQL needed for tests. Rate limiting is disabled automatically.

## Godot Setup

1. Open Godot 4.
1. Click Import or Open.
1. Select the project folder: `code/client`.

Godot notes:

- Do not commit `.godot/` cache.
- Only commit project/source content such as `project.godot`, scenes, scripts, and assets.
- Do not commit `.import/`.

## Troubleshooting

### ModuleNotFoundError

- Make sure the venv is activated: `.\.venv\Scripts\Activate.ps1`.
- Reinstall dependencies: `pip install -r requirements.txt`.
- Confirm you are in `code/server` when running backend commands.

### .env Not Found

- Create it from the example:

```powershell
Copy-Item .env.example .env
```

### Database Connection Failed

- Ensure PostgreSQL is running: `psql -U wanderville_admin -d wanderville -c "SELECT 1"`
- Check your `DATABASE_URL` in `.env` has the correct credentials
- Run `python -m alembic upgrade head` to apply migrations
- If you need to reset: `psql -U wanderville_admin -d wanderville -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"` then re-run migrations

### Alembic Says SQLite And Fails On An Existing Table

- Confirm the database URL in `.env` points to the database you intended to use.
- Check for leftover SQLite files with `Get-ChildItem -Recurse *.db`.
- If the database is disposable, delete the matching `.db` file and rerun `python -m alembic upgrade head`.
- If you need to keep the data, inspect the Alembic state with `python -m alembic current` and align the schema history instead of rerunning the migration blindly.

### Username Already Taken

- Sign up with a different username, or reset your PostgreSQL database

### Port 8000 Already In Use

- Stop the process using port 8000, or run the server on another port:

```powershell
uvicorn main:app --reload --port 8001
```

## World & Map Setup

Every player automatically gets a **World** created when they sign up. The world stores a `tiles` dictionary that maps coordinate keys (e.g. `"0,0"`, `"1,0"`) to tile types (e.g. `"grass"`, `"dirt"`).

### How it works

1. When a player signs up via `POST /auth/signup`, the backend creates a `World` row linked to that player.
2. The world starts with an empty `tiles` dictionary and the default name `"My World"`.
3. You can access the global world state via `GET /world/state`.

### Farming

- Players can plant, water, and harvest crops on a farm grid.
- Supported crops: paddy, wheat, sugarcane, sweet_corn, bell_pepper, green_bean, pumpkin, apple, turnip, potato, carrot, cabbage, strawberry, lettuce, pea, radish, moonflower, rivermint, sunbloom, ancient_grain.
- Crops grow through 3 stages with configurable growth times per crop type.

### Inventory

- Each player has an inventory that stores item stacks by type.
- Items can be added, removed, and transferred between players.
- Inventory is unique per player per item type (quantities stack).

### Economy

- Players have a **taka** balance used for buying seeds from the catalog.
- XP is earned by harvesting and levels up the player.
- Economy data is created automatically on first access.
