# Wanderville backend update

This package extends the uploaded backend; it is not a replacement Godot client. **No client file was edited: all 1,119 client files match the supplied archive byte-for-byte.** The package contains `code/server` and documentation only. Existing uncommitted client work in the uploaded Git tree was preserved.

## What was built

The existing FastAPI / SQLAlchemy / Alembic organization is retained. New domain modules sit beside auth, players, economy, inventory, farming and world. Each domain has models, a repository, a service and a router; request schemas accompany routes that accept bodies. Repositories share bounded ORM primitives in `core/gameplay.py`. Service methods own transaction boundaries and use existing inventory/economy helpers without nested commits.

| Domain | Backend capability |
| --- | --- |
| Profile | Character/map preferences, saved audio/display settings, status, tutorial sequence, first-encounter hints, feedback, authenticated account deletion, heartbeat/save timestamps |
| Inventory/shop | Six inventory partitions, per-partition slot limits and stack limits, distinct seed codes, catalog previews, level checks, daily stock rotation, idempotent purchases, sales, persistent collection/fish logs, rare-item discard confirmation |
| Farming | Existing till/plant/water/harvest contract retained, new seeds map to produce, bucket charges/refill, lifetime harvest counter, progression hooks |
| Housing | Starter house, tier/level/cost checks, atomic upgrades, inventory-backed outdoor decorations |
| Pets | Adoption after character selection, saved name, feeding, affection, accessories, timed fetch and idle/rest state |
| Fishing | Owned rod checks, water-location and frozen-lake checks, server-chosen catch and bite timing, two-second catch window, XP, five-minute overflow drops |
| Social | Canonical friend pairs, recipient-only acceptance, block/unblock, public friend profiles, farm visits/read-only farm data, expiring invitations, escrowed gifts, atomic trade acceptance, filtered direct messages, reports |
| Progression | Trusted gameplay events, automatic achievement/task rewards, per-game-day task progress, UTC login streak/reward, level-up notifications |
| Notifications/events | Private inbox, unread count/read/dismiss, crop-ready and rain alerts, invitation-expiry alerts, timed world-event claims |
| Multiplayer | Persisted room/position/sequence, shared database snapshots, reconnect window, movement speed checks, campus polygon checks, nearby text and emotes, authenticated WebSocket stream |

The database now has **41 application tables**, compared with 11 in the uploaded baseline. There are **51 catalog items**: 22 original crops, 22 distinct seeds, and seven fishing/pet/decoration items. New balancing values are explicit initial choices, not values stated by the SRS.

## Apply the package

1. Back up your existing project and database.
2. Extract this archive **into the existing Wanderville root**, merging `code/server` and `docs`. It has no `code/client` directory and does not include `.env`, local databases, Git history, caches or credentials.
3. Keep your existing `.env`; use `.env.example` only if setting up a new environment. The database remains **PostgreSQL** in staging/production. Neon is a hosted PostgreSQL option, not a different database engine.
4. Install dependencies, migrate, seed, then start the API and worker.

PowerShell, from the project root:

```powershell
cd code/server
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements-dev.txt
# Configure DATABASE_URL and JWT_SECRET_KEY in .env before the next commands.
python -m alembic upgrade head
python -m app.db.seed
python -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

In a second terminal, activate the same environment and run:

```powershell
cd code/server
.\.venv\Scripts\Activate.ps1
python -m app.modules.world.worker
```

The worker provides crop-ready/rain notifications and timed rare events; it is not automatically started in every API process. For a single bounded sweep, use `python -m app.modules.world.worker --once`.

On Bash, activate with `source .venv/bin/activate`; the other Python commands are identical. Open `http://127.0.0.1:8000/docs` for request schemas. Existing email verification still requires configured SMTP. The automated tests replace email delivery with a test mailbox; they do not send real emails.

## Migration and persistence

- `0001_initial_schema` stays the baseline.
- `0002_gameplay` adds domain tables and backfills profiles/starter houses for existing players. It does not erase accounts, inventory, farms or balances.
- `0003_presence` adds presence and proximity-message delivery tables.
- `0004_boolean_defaults` explicitly normalizes PostgreSQL Boolean defaults. Historical revisions are unchanged; Alembic `env.py` renders their numeric Boolean defaults portably so fresh PostgreSQL upgrades can reach the repair revision.
- `python -m app.db.seed` seeds reference items, item rules, house tiers, fishing spots and goals; it also backfills collection entries from owned inventory. Run it after migrating.
- `docs/database/POSTGRES_SCHEMA.sql` is generated offline PostgreSQL DDL for review or a fresh empty database. **Do not execute that whole file on an existing database and do not combine it with a second baseline creation. Use Alembic for normal upgrades.**
- Every successful gameplay mutation commits immediately. The profile save endpoint records a save acknowledgement; it does not accept arbitrary client JSON or overwrite balances/XP from a client snapshot.
- Downgrades remove the new features' tables and data. Back up before downgrading; this update does not run a downgrade on your database.

## Verify

From `code/server`:

```powershell
python -m pytest -q
python -m ruff check app migrations tests scripts
python scripts/verify_client_unchanged.py
```

SQLite is used only for isolated local tests by default. The tests never use your `.env` database. PostgreSQL row-lock concurrency requires a separate, disposable database whose name ends in `_test`:

```powershell
$env:WANDERVILLE_TEST_DATABASE_URL = "postgresql+psycopg2://USER:PASSWORD@127.0.0.1:5432/wanderville_test"
$env:WANDERVILLE_ALLOW_TEST_RESET = "1"
python -m pytest -q
Remove-Item Env:WANDERVILLE_TEST_DATABASE_URL
Remove-Item Env:WANDERVILLE_ALLOW_TEST_RESET
```

The test suite clears all application tables in that explicitly selected test database. Never point it at your development, Neon live, or production database. PostgreSQL concurrency cases cover double-spend, double-harvest, refresh rotation, reciprocal transfers, duplicate planting, purchase replay, duplicate gift claims and simultaneous trade acceptance.

## Important integration boundaries

The supplied Godot code still keeps much farming state locally and does not call most new routes. Therefore this is **tested backend functionality, not a claim that every SRS screen/animation is already playable in the unchanged client**. See `SRS_BACKEND_AUDIT.md` and `NEW_API_REFERENCE.md`.

- Visual pet following/fetch, smooth remote-player interpolation, seasonal effects, badges, tooltips and all new screens need a separately authorized client task.
- The backend uses a snapshot of the supplied campus water/collision polygons, including the world scene's map translation. It does not extract every TileSet/building collider or reproduce the player's collision shape; Godot's full physics remains a client responsibility. Re-export/review backend geometry if the map changes.
- WebSocket clients authenticate with an initial message, then receive roughly 5 Hz idle snapshots. Send sequenced movement/heartbeat positions while connected. A room is limited to a bounded 200 nearby candidates per snapshot. This is suitable for a small project deployment, not a benchmarked large-scale MMO transport.
- Reconnect restores persisted position for 60 seconds; after that, entering resets to the main-gate spawn. Smooth movement and title-screen behavior must be implemented by the client.
- Invites currently target the inviter's personal farm. The SRS wording “inviter's location” is broader; arbitrary in-map coordinate teleport invitations are not implemented.
- Daily tasks use the existing in-game day clock. Login streaks use UTC calendar days, with 10 Aura per successful first login that day. Reward sizes, house prices, item prices, pet cooldowns and capacities are defaults to tune.
- Rain is deterministically scheduled every fourth game day; winter uses snow. During rain the worker waters active stages without consuming bucket charges. No historical offline weather replay is attempted if the worker was stopped.
- Rare-event opportunities run for five minutes every seventh in-game day. Event rewards can be claimed once per account; no event-specific minigame or scene was added.
- Text filtering is a configurable whole-word baseline, not comprehensive multilingual moderation. Reports are persisted; no moderator UI/workflow was part of this change.
- Friend lists and several small collections are bounded. Notification and gift inboxes provide cursors; scaling past the documented limits needs additional pagination and load testing.
- Original crop codes remain accepted as plantable inventory for compatibility. New callers should buy and plant `<crop>_seed` and receive `<crop>` after harvesting. The old client inventory renderer still needs a future partition-aware integration.
- Account deletion cascades the account's social history, sent/received gifts and pending trades. Claimed items owned by another account remain with that account. An unclaimed gift disappears if either participant deletes their account; this is an explicit retention policy choice.

No claim of “highest possible optimization” is made without production load measurements. Implemented safeguards include foreign keys/check constraints, canonical friendship uniqueness, indexed mailbox/room/expiry queries, bounded reads, batched nearby-player/name/block lookups, ordered PostgreSQL player locks, replay keys, and atomic currency/inventory transfers.
