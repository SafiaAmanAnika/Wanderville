# WanderVille backend implementation report

Completed 30 September 2026 against the supplied working-tree ZIP and both instruction files.
The database addendum explicitly superseded the original preserve-migrations instruction.

## Result

The existing backend was replaced with one domain-based implementation for auth,
players, world, inventory, economy/XP and farming. PostgreSQL models and a clean
Alembic baseline define 11 application tables. Godot request paths and payloads
are preserved. No existing application database was accessed or dropped.

**Validation: 74 tests passed; 5 PostgreSQL concurrency tests were skipped.**
The application started under Uvicorn and `/health`, `/docs`, `/openapi.json`
returned HTTP 200. Ruff and Python compilation passed. One dependency emits a
non-failing Starlette/AnyIO deprecation warning. A separate live-HTTP smoke pass
replayed the exact frozen-client payloads against a running Uvicorn process on a
disposable SQLite database.

**All 1,120 client files retain their original SHA-256 hashes.** This includes
548 files outside `.godot/` and 572 Godot cache files. The previously delivered
archive and the OpenCode-reviewed upload contain exactly the same client bytes;
the two file counts describe different scopes, not missing files.

In the supplied repository on this Linux filesystem, `git status --short
code/client` has 59 entries, exactly matching the pre-refactor snapshot.
Of these, 49 are CRLF/LF-only differences, nine are lowercase tracked menu paths
whose files exist under the supplied capitalized directories, and one is the
pre-existing `project.godot` edit removing `window/stretch/aspect="keep"`.
Git's line-ending and filesystem case handling can produce different local
status output. No client checkout, restore, rename, reset, cleanup or Godot
regeneration was performed. See [the follow-up review](OPENCODE_REVIEW.md).

## 1. Old and new structure

Old: responsibilities were split among `app/api`, `models`, `schemas`, `services`
and `deps`; the root entrypoint mixed setup, logging and migration execution.
New: `app/core`, `app/db`, and `app/modules/{auth,players,world,inventory,economy,farming}`.
Each implemented domain keeps its schemas, rules, queries and models together.
The root entrypoint only imports/exports `app.main.app`.

Routers handle HTTP; services own business rules and a single transaction;
repositories handle queries and flushing; models represent persistence. There
are no duplicate active implementations or unused scheduler/WebSocket placeholders.

## 2. Replacements and removals

| Original | Replacement |
| --- | --- |
| root main.py application setup | app/main.py; root compatibility import retained |
| app/config.py | app/core/config.py |
| app/database.py | app/db/base.py, session.py, model_registry.py |
| app/seed_data.py | app/db/seed.py and catalog.json |
| app/api, models, schemas, services auth/player code | app/modules/auth and players |
| scattered inventory/economy/world/farm code | corresponding app/modules domain |
| app/deps authentication/rate limit | auth/dependencies.py and core/rate_limit.py |
| old seven Alembic revisions | reviewed 0001_initial_schema.py |
| root-level tests and local database cleanup fixture | isolated domain/contract/database suite |
| empty scheduler/websocket placeholders | removed; no speculative replacement |

All old models, routes, catalog values, columns, indexes, foreign keys and revision
relationships were recorded before deletion in `docs/database/LEGACY_AUDIT.md`.
The original uploaded archive and original Git history were not rewritten.

## 3. Database changes

Old tables: players, refresh_tokens, worlds, item_definitions, inventory_items,
player_economy, player_experience, farm_plots, world_state.

New tables: players, refresh_tokens, account_tokens, item_definitions,
player_worlds, player_economy, economy_transactions, player_experience,
inventory_items, farm_tiles, world_state.

- Replaced worlds with player_worlds and farm_plots with reusable farm_tiles.
- Removed position, verification-token and reset-token columns from Player.
  Verification/reset tokens now have typed, expiring, single-use rows.
- Replaced taka_balance/coin_balance persistence with Aura. Added an atomic signed
  transaction ledger. Kept legacy API fields at the boundary.
- Derived current XP and the next threshold from total XP; kept level consistent
  on grants. Removed the unused stored title.
- Removed unexplained world tiles JSON and stored continuously changing time of day.
- Added crop progress and timestamps, per-world coordinate uniqueness, and checks
  for valid empty/planted/watered farm state.
- Added positive inventory, nonnegative balance/XP, positive level and catalog
  checks; token hash uniqueness; unique world owner; canonical item references.
- All dependent private records cascade on player deletion; tiles cascade on
  world deletion. Item definitions survive account deletion.
- All application timestamps are timezone-aware UTC; PostgreSQL uses TIMESTAMPTZ.
- The explicit idempotent seed retains all 22 original catalog definitions and
  initializes the global environment singleton without resetting its clock.

Full column/constraint/index documentation is in `docs/database/SCHEMA.md` and
relationships in `ERD.md`. No tables were added for unimplemented future domains.

## 4. Migration baseline and reset

Old head `005_add_auth_upgrade` and its six ancestors were audited and replaced.
New head: `0001_initial_schema`, with no parent. Upgrade creates tables in
foreign-key order; downgrade removes children before parents. Portable boolean
and timestamp defaults were manually reviewed after generation.

This is a fresh-development-schema rebuild, not a migration of old user data.
Use a new local database or the explicit local reset commands in
`docs/database/RESET.md`. Startup does not reset, migrate, create tables, or seed.
Do not stamp the old schema as the new head.

## 5. API compatibility

All 23 request shapes in the existing APIClient are covered by the route/contract
suite. Login still returns access_token, refresh_token, token_type and player
under data. Inventory always returns item_code. Plant accepts item_code and a
legacy crop_type alias. Legacy item_type is confined to schema adapters.

The Aura API keeps taka_balance as an alias and coin_balance=0 as an explicit
legacy placeholder. Player positions are response-only zero values. World tiles
is a response-only empty object. The two unused arbitrary map-JSON PUT routes
return HTTP 410; they were not called by the supplied Godot client.

Additive APIs: POST /farm/till and GET /economy/transactions. Existing auth
refresh/logout/change-password routes remain. Every error code the frozen client
branches on is now reachable: the login UI's EMAIL_NOT_VERIFIED and
ACCOUNT_LOCKED, the signup UI's USERNAME_TAKEN and EMAIL_TAKEN, and the
verification/reset screens' TOKEN_EXPIRED, ALREADY_VERIFIED and INVALID_TOKEN.
Details: `docs/API_CONTRACT.md`.

## 6. Bugs and security fixes

- Account-link error codes now match the client. An expired verification or reset
  link previously answered `EXPIRED_TOKEN`, which no client screen checks, so an
  expired link fell through to the "Invalid Link" dead end that hides the Resend
  button. It now answers `TOKEN_EXPIRED`. A spent verification link for an
  already-verified account now answers `ALREADY_VERIFIED` instead of
  `INVALID_TOKEN`, which makes the client's existing "Already Verified" screen
  reachable. A spent reset link still answers `INVALID_TOKEN`, as the client
  expects. Both are regression-tested.

- Removed missing farming method/constant references and conflicting crop names.
- Implemented four visible stages and one watering per stage, with saved progress,
  dry pauses, seasonal growth-rate integration, and reusable harvested tiles.
- Planting consumes inventory and grants XP; harvest rewards inventory/XP
  atomically. A repeated harvest cannot award another reward.
- Signup, transfer, currency/ledger updates and harvest fully roll back on failure.
- PostgreSQL player-row locks serialize game mutations; transfers acquire locks
  in sorted player-ID order. Refresh rotation uses locks to allow one successor.
- Enforced authentication, ownership, positive quantities/amounts/XP and stack size.
- Arbitrary item/currency/XP grants are dev/test-only. Global season mutation is
  disabled by default and requires an explicit development switch.
- Preserved Argon2, JWT access tokens, hashed refresh/account tokens, lockout,
  email verification and password reset. Password changes invalidate all sessions.
- Google ID tokens require a configured audience and Google's signature/claim
  verification. Untrusted same-email identities cannot silently link an account;
  Google login never re-enables a disabled account.
- Removed secret logging and insecure production defaults. Unified errors,
  configuration-driven CORS and bounded local rate limiting are centralized.

## 7. Validation evidence and limits

| Check | Result |
| --- | --- |
| Full pytest suite | 74 passed, 5 skipped, 0 failed |
| Godot routes and representative exact payloads | Passed |
| Signup/transfer/ledger/harvest injected failure rollback | Passed |
| Database constraints and deletion cascades | Passed on SQLite with foreign keys enabled |
| Alembic upgrade, check, current, heads, history | Passed on isolated SQLite; one head; no schema difference |
| Baseline downgrade/re-upgrade | Passed on a fresh temporary SQLite database |
| PostgreSQL offline migration SQL generation | Passed; reviewed PostgreSQL DDL defaults and FK order |
| Actual PostgreSQL migration/schema/constraint execution | Not run: no usable PostgreSQL server in this workspace |
| PostgreSQL concurrent spend/harvest/plant/refresh/transfer | Five tests supplied, skipped here |
| Real SMTP or Google account sign-in | Not exercised; external services mocked in tests |
| Uvicorn and actual HTTP /health, /docs, /openapi.json | Passed |
| Ruff check / Ruff format --check / compileall | Passed |
| Client SHA-256 and Git status | Exact match with pre-refactor snapshots |

SQLite does not validate PostgreSQL row-lock behavior. The setup guide includes
commands to run the entire suite against a separate disposable PostgreSQL
`*_test` database with an explicit reset opt-in. No claim of PostgreSQL runtime
validation or complete client gameplay synchronization is made.

## 8. Exact local run commands

Create a new PostgreSQL database and edit `.env` as described in
`docs/DATABASE_SETUP.md`, then from the repository root:

```powershell
cd code/server
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements-dev.txt
if (!(Test-Path .env)) { Copy-Item .env.example .env }
# Set DATABASE_URL and a random JWT_SECRET_KEY in .env.
python -m alembic upgrade head
python -m app.db.seed
python -m alembic check
python -m pytest -q
python -m uvicorn main:app --reload --no-access-log
```

In development, open the verification email in `.dev-mail/`; no actual email is
sent. New accounts have empty inventory and zero Aura by default. Give a test
account wheat using the dev-only inventory/add API before testing farming.

## 9. Remaining client and SRS integration

Backend farming API is ready, but current Godot farming gameplay remains partly
local and therefore cannot be fully synchronized/persisted without future client
integration. The frozen client still owns crop actions and water, leaves fetched
crop reconstruction unfinished, and does not apply fetched Aura/season values.
Google browser redirect/deep-link handoff and automatic refresh/logout wiring
also remain integration work.

Distinct seed/produce partitions, partition capacities, sale/shop logic, lifetime
harvest statistics, scheduled weather/rain watering and larger future gameplay
systems are not implemented. No speculative schemas or empty modules were added
for them. See `docs/BACKEND_CLIENT_INTEGRATION_GAPS.md` for the precise scope.

## 10. Applying the package

Extract into a separate directory. Preserve your local `.env` and virtualenv.
Replace the backend source, migrations and tests as a set so removed legacy
files do not survive an overlay. Keep your current code/client directory intact;
the ZIP also contains an identical copy of the uploaded client. Copy the updated
README/docs as needed. The distributable omits Git metadata, Python environments,
credentials, development email tokens and caches outside the frozen client.

## 11. Files created

- `code/server/app/__main__.py`
- `code/server/app/core/__init__.py`
- `code/server/app/core/clock.py`
- `code/server/app/core/config.py`
- `code/server/app/core/exceptions.py`
- `code/server/app/core/logging.py`
- `code/server/app/core/rate_limit.py`
- `code/server/app/core/responses.py`
- `code/server/app/db/__init__.py`
- `code/server/app/db/base.py`
- `code/server/app/db/catalog.json`
- `code/server/app/db/model_registry.py`
- `code/server/app/db/seed.py`
- `code/server/app/db/session.py`
- `code/server/app/db/timestamps.py`
- `code/server/app/main.py`
- `code/server/app/modules/__init__.py`
- `code/server/app/modules/auth/__init__.py`
- `code/server/app/modules/auth/dependencies.py`
- `code/server/app/modules/auth/email.py`
- `code/server/app/modules/auth/email_validation.py`
- `code/server/app/modules/auth/models.py`
- `code/server/app/modules/auth/oauth.py`
- `code/server/app/modules/auth/repository.py`
- `code/server/app/modules/auth/router.py`
- `code/server/app/modules/auth/schemas.py`
- `code/server/app/modules/auth/security.py`
- `code/server/app/modules/auth/service.py`
- `code/server/app/modules/economy/__init__.py`
- `code/server/app/modules/economy/models.py`
- `code/server/app/modules/economy/repository.py`
- `code/server/app/modules/economy/router.py`
- `code/server/app/modules/economy/schemas.py`
- `code/server/app/modules/economy/service.py`
- `code/server/app/modules/farming/__init__.py`
- `code/server/app/modules/farming/models.py`
- `code/server/app/modules/farming/repository.py`
- `code/server/app/modules/farming/router.py`
- `code/server/app/modules/farming/schemas.py`
- `code/server/app/modules/farming/service.py`
- `code/server/app/modules/inventory/__init__.py`
- `code/server/app/modules/inventory/models.py`
- `code/server/app/modules/inventory/repository.py`
- `code/server/app/modules/inventory/router.py`
- `code/server/app/modules/inventory/schemas.py`
- `code/server/app/modules/inventory/service.py`
- `code/server/app/modules/players/__init__.py`
- `code/server/app/modules/players/models.py`
- `code/server/app/modules/players/repository.py`
- `code/server/app/modules/players/schemas.py`
- `code/server/app/modules/world/__init__.py`
- `code/server/app/modules/world/models.py`
- `code/server/app/modules/world/repository.py`
- `code/server/app/modules/world/router.py`
- `code/server/app/modules/world/schemas.py`
- `code/server/app/modules/world/service.py`
- `code/server/migrations/versions/0001_initial_schema.py`
- `code/server/pytest.ini`
- `code/server/requirements-dev.txt`
- `code/server/tests/auth/test_auth.py`
- `code/server/tests/auth/test_configuration.py`
- `code/server/tests/contract/test_godot_contract.py`
- `code/server/tests/database/test_constraints.py`
- `code/server/tests/database/test_migrations.py`
- `code/server/tests/database/test_postgres_concurrency.py`
- `code/server/tests/economy/test_economy.py`
- `code/server/tests/farming/test_farming.py`
- `code/server/tests/inventory/test_inventory.py`
- `code/server/tests/world/test_world.py`

Documentation created/updated: README.md; docs/BACKEND_STRUCTURE.md;
docs/API_CONTRACT.md; docs/DATABASE_SETUP.md;
docs/BACKEND_CLIENT_INTEGRATION_GAPS.md; docs/IMPLEMENTATION_REPORT.md;
docs/MANUAL_BACKEND_TEST_GUIDE.md; docs/OPENCODE_REVIEW.md;
docs/OPENCODE_RUN_FIX_PROMPT.md; and docs/database/{LEGACY_AUDIT,SCHEMA,ERD,RESET,SEEDING}.md.
The former doc/setup guides were merged into these documents; there is one
documentation root, docs/.

## 12. Legacy files deleted

- `code/server/.gitkeep`
- `code/server/app/api/__init__.py`
- `code/server/app/api/auth.py`
- `code/server/app/api/economy.py`
- `code/server/app/api/farm.py`
- `code/server/app/api/health.py`
- `code/server/app/api/inventory.py`
- `code/server/app/api/world.py`
- `code/server/app/config.py`
- `code/server/app/database.py`
- `code/server/app/deps/__init__.py`
- `code/server/app/deps/auth.py`
- `code/server/app/deps/rate_limit.py`
- `code/server/app/models/.gitkeep`
- `code/server/app/models/__init__.py`
- `code/server/app/models/economy.py`
- `code/server/app/models/experience.py`
- `code/server/app/models/farm.py`
- `code/server/app/models/inventory.py`
- `code/server/app/models/item.py`
- `code/server/app/models/player.py`
- `code/server/app/models/refresh_token.py`
- `code/server/app/models/world.py`
- `code/server/app/scheduler/.gitkeep`
- `code/server/app/scheduler/__init__.py`
- `code/server/app/schemas/.gitkeep`
- `code/server/app/schemas/auth.py`
- `code/server/app/schemas/economy.py`
- `code/server/app/schemas/farm.py`
- `code/server/app/schemas/inventory.py`
- `code/server/app/schemas/player.py`
- `code/server/app/schemas/responses.py`
- `code/server/app/schemas/world.py`
- `code/server/app/seed_data.py`
- `code/server/app/services/.gitkeep`
- `code/server/app/services/auth_service.py`
- `code/server/app/services/economy_service.py`
- `code/server/app/services/email_service.py`
- `code/server/app/services/email_validation.py`
- `code/server/app/services/farm_service.py`
- `code/server/app/services/inventory_service.py`
- `code/server/app/services/oauth_service.py`
- `code/server/app/services/world_service.py`
- `code/server/app/websocket/.gitkeep`
- `code/server/app/websocket/__init__.py`
- `code/server/migrations/versions/001_initial_schema.py`
- `code/server/migrations/versions/002_add_world_table.py`
- `code/server/migrations/versions/003_add_fk_cascade.py`
- `code/server/migrations/versions/004_add_persistence_layer.py`
- `code/server/migrations/versions/005_add_auth_upgrade.py`
- `code/server/migrations/versions/39e5dd4b1af7_add_farm_plots_table.py`
- `code/server/migrations/versions/fe33f4e10006_add_inventory_items_table.py`
- `code/server/tests/.gitkeep`
- `code/server/tests/test_auth.py`
- `code/server/tests/test_auth_deps.py`
- `code/server/tests/test_inventory.py`
- `code/server/tests/test_world.py`
- `code/server/tests/test_world_service.py`

## 13. Final backend tree

```text
code/server/
├── app/
│   ├── core/
│   │   ├── __init__.py
│   │   ├── clock.py
│   │   ├── config.py
│   │   ├── exceptions.py
│   │   ├── logging.py
│   │   ├── rate_limit.py
│   │   └── responses.py
│   ├── db/
│   │   ├── __init__.py
│   │   ├── base.py
│   │   ├── catalog.json
│   │   ├── model_registry.py
│   │   ├── seed.py
│   │   ├── session.py
│   │   └── timestamps.py
│   ├── modules/
│   │   ├── auth/
│   │   │   ├── __init__.py
│   │   │   ├── dependencies.py
│   │   │   ├── email.py
│   │   │   ├── email_validation.py
│   │   │   ├── models.py
│   │   │   ├── oauth.py
│   │   │   ├── repository.py
│   │   │   ├── router.py
│   │   │   ├── schemas.py
│   │   │   ├── security.py
│   │   │   └── service.py
│   │   ├── economy/
│   │   │   ├── __init__.py
│   │   │   ├── models.py
│   │   │   ├── repository.py
│   │   │   ├── router.py
│   │   │   ├── schemas.py
│   │   │   └── service.py
│   │   ├── farming/
│   │   │   ├── __init__.py
│   │   │   ├── models.py
│   │   │   ├── repository.py
│   │   │   ├── router.py
│   │   │   ├── schemas.py
│   │   │   └── service.py
│   │   ├── inventory/
│   │   │   ├── __init__.py
│   │   │   ├── models.py
│   │   │   ├── repository.py
│   │   │   ├── router.py
│   │   │   ├── schemas.py
│   │   │   └── service.py
│   │   ├── players/
│   │   │   ├── __init__.py
│   │   │   ├── models.py
│   │   │   ├── repository.py
│   │   │   └── schemas.py
│   │   ├── world/
│   │   │   ├── __init__.py
│   │   │   ├── models.py
│   │   │   ├── repository.py
│   │   │   ├── router.py
│   │   │   ├── schemas.py
│   │   │   └── service.py
│   │   └── __init__.py
│   ├── __init__.py
│   ├── __main__.py
│   └── main.py
├── migrations/
│   ├── versions/
│   │   └── 0001_initial_schema.py
│   ├── env.py
│   └── script.py.mako
├── tests/
│   ├── auth/
│   │   ├── test_auth.py
│   │   └── test_configuration.py
│   ├── contract/
│   │   └── test_godot_contract.py
│   ├── database/
│   │   ├── test_constraints.py
│   │   ├── test_migrations.py
│   │   └── test_postgres_concurrency.py
│   ├── economy/
│   │   └── test_economy.py
│   ├── farming/
│   │   └── test_farming.py
│   ├── inventory/
│   │   └── test_inventory.py
│   ├── world/
│   │   └── test_world.py
│   └── conftest.py
├── .env.example
├── .gitignore
├── alembic.ini
├── main.py
├── pytest.ini
├── requirements-dev.txt
└── requirements.txt
```
