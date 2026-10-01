# Backend verification results

Verified on 2026-10-01 (Asia/Dhaka) in the existing Wanderville checkout. These results supersede the earlier SQLite-only report. Existing uncommitted server/client changes were preserved. No live/user database was migrated or reset; nothing was deployed, pushed, or sent to another person.

## Final results

| Check | Actual result |
| --- | --- |
| Server environment | Used `code/server/.venv-verify/Scripts/python.exe` (Python 3.12), a server-only virtual environment; installed `requirements-dev.txt` successfully |
| Dependency consistency | `pip check`: No broken requirements found |
| Ruff | All checks passed |
| Python compilation | Passed for app, migrations, tests and scripts |
| Complete SQLite suite | **132 passed, 8 skipped, 1 warning; 55.72 seconds** |
| Complete real PostgreSQL suite | **140 passed, 0 skipped, 1 warning; 81.97 seconds** |
| PostgreSQL concurrency | **8 passed**: all original seven plus simultaneous trade acceptance |
| Fresh migration / ORM parity | Passed on SQLite and PostgreSQL through `0001_initial_schema -> 0002_gameplay -> 0003_presence -> 0004_boolean_defaults`; no metadata differences |
| Migration round trip | Fresh disposable databases/schemas successfully upgraded, downgraded to base and upgraded again |
| Populated 0001 upgrade | Passed on SQLite and PostgreSQL; complete existing rows in players, economy, XP, catalog, inventory, worlds and planted farm tiles were identical afterward; profiles/houses backfilled |
| Reference seeding twice | Passed; no table-count growth, 51 catalog items, 41 application tables; season/day anchors and complete world clock retained |
| Live API | Separate Uvicorn process: `/health` 200, `/openapi.json` 200, 86 paths; both accounts authenticated and read profile/shop/housing/notifications/progression; unauthenticated profile rejected 401 |
| Live social smoke | Friend request/accept and private friend farm read passed over real HTTP |
| Live worker | Separate continuous worker process ran alongside API and generated one scheduled world event; bounded standalone CLI regression also passed |
| Live WebSockets | Two authenticated sockets received snapshots, movement and proximity chat; sequence replay 409, invalid token 401, malformed close 1008, oversized close 1009 |
| Client current snapshot | **1,119 initial / 1,119 final files; zero SHA-256 changes, additions or removals** |
| Original upload manifest | Initial and final comparison both passed for all 1,119 files |
| Existing client Git changes | `code/client/project.godot` remained modified exactly as at start; never reverted |

The only warning is Starlette's deprecated `anyio.abc.BlockingPortal` alias. SQLite skips the eight PostgreSQL-only concurrency cases; those same cases actually passed on PostgreSQL. The PostgreSQL run's two isolated migration schemas also used PostgreSQL; the worker CLI regression intentionally uses temporary SQLite in both runs.

## Defects repaired

1. A fresh real PostgreSQL migration failed at `fishing_spots.freezes_in_winter`: revision 0002 emitted `BOOLEAN DEFAULT 0`, which PostgreSQL rejects. Historical revisions 0001/0002/0003 remain unchanged. A scoped Alembic table-DDL listener renders Boolean 0/1 defaults as false/true on PostgreSQL, including offline SQL. New revision `0004_boolean_defaults` explicitly normalizes the twelve affected gameplay defaults for existing PostgreSQL deployments. It changes no gameplay rows, columns or balances; SQLite's equivalent defaults stay intact. Adding only a later revision would not allow a fresh PostgreSQL database to get past the failing 0002, so both the rendering fix and explicit new revision are required.
2. WebSocket malformed JSON previously returned without an explicit close frame. It now closes with 1008, including the initial authentication timeout.
3. WebSocket limits previously counted Unicode characters rather than UTF-8 bytes. An oversized multibyte payload could bypass the advertised 8-KiB limit. Both initial and subsequent packets now enforce byte length and close with 1009.
4. Binary packets previously failed inside text reception. The protocol now explicitly rejects them with 1003 without swallowing unrelated service errors.

## Files changed in this verification session

Pre-existing changes listed by Git are not attributed to this session.

| File | Why |
| --- | --- |
| `code/server/migrations/env.py` | Portable historical Boolean DDL rendering, listener removed after each migration run |
| `code/server/migrations/versions/0004_portable_boolean_defaults.py` | Explicit additive default repair; supports online/offline PostgreSQL |
| `code/server/app/modules/realtime/router.py` | Byte limits and explicit malformed/binary/timeout closure |
| `code/server/tests/gameplay/test_validation.py` | 26 additional adversarial checks, including ten frame cases and three Google deletion identity boundary cases |
| `code/server/tests/database/test_postgres_concurrency.py` | Simultaneous trade acceptance: one winner, one closed-trade result, exactly one exchange |
| `code/server/tests/database/test_migrations.py` | PostgreSQL isolated schema migration testing and full populated baseline row preservation |
| `code/server/tests/database/test_constraints.py` | Repeated seed comparison of every table count and both world-clock anchors |
| `code/server/scripts/smoke_backend.py` | Reproducible real API/worker/WS harness; refuses any nonempty or non-PostgreSQL/non-`*_test` database |
| `code/server/.gitignore` | Exclude `.verification/` disposable PostgreSQL data, logs, test outputs and hash snapshots; no root config changed |
| `docs/database/POSTGRES_SCHEMA.sql` | Correct offline DDL through 0004; inspection artifact, not an existing-database upgrade script |
| `docs/BACKEND_UPDATE_GUIDE.md` | New revision and eighth concurrency check |
| `docs/NEW_API_REFERENCE.md` | UTF-8 limits, close codes and precise token revocation semantics |
| `docs/BACKEND_INTEGRATION_CHECKLIST.md` | Exact read-only Godot files/functions and missing payload/response mappings |
| `docs/VERIFICATION_RESULTS.md` | Current commands, counts, evidence and limitations |

## Coverage evidence

Existing tests plus the added adversarial cases cover:

- Friends: request/recipient acceptance/remove/block/unblock, private profiles/farms and nonfriend rejection. Gifts: escrow, request replay, recipient privacy, duplicate claims and full-inventory rollback. Trades: proposal, missing offers, cancel, decline, rollback and simultaneous acceptance; blocked interactions are checked in social/realtime tests.
- Purchases: server catalog price/level, insufficient balance, request-ID replay and payload conflict, stack/partition overflow and balance/inventory rollback. Sales, persistent collection entries and rare-discard confirmation remain covered. Distinct seeds map to crop produce while legacy farm payload contracts remain covered by contract/farming tests.
- Fishing: actual configured water polygon, owned rod and level gate, winter freeze, early/late catch, exact two-second endpoint and 2.001-second rejection, server-selected hidden reward, exact reward XP, replay rejection, overflow drops, private claims and expired drops. Overflow expiration is created as catch time plus five minutes; clients cannot submit reward codes.
- Pets/housing: repeated character selection creates one pet, rename/feed/accessory persistence, invalid food/ownership rejection, last-item accessory cleanup, fetch cooldown and replay rejection; upgrade level/tier/balance gates and rollback.
- Progression/worker: trusted plant/harvest/catch/sale/login hooks, same-transaction goal awards, one-time achievements/dailies, consecutive/gapped UTC login streaks, in-game day rollover, rain watering, crop-ready and invitation-expiry deduplication, timed claims and replay.
- Realtime: HTTP auth, first-message WS auth, URL-token rejection, invalid/expired/credential-revoked access tokens, malformed/binary/oversized messages, sequence replay/speed rejection, a known campus collision polygon, proximity chat recipients, blocks, private room authorization, emote/reconnect expiry. Snapshot steps release ORM transactions; query capture proves batched nearby/name lookups (bounded query count for multiple players).
- Profile: attempted currency/XP/inventory writes leave authoritative state untouched; ordered tutorial and one-time hints; bounded private feedback/reports; username/password deletion; missing/mismatched/matching verified Google identity boundary; cascades and retention of another player's claimed gift inventory.

Google deletion identity tests stub only the verified-identity boundary. Existing auth tests cover provider verification/claim rejection. No real Google credential or SMTP provider was contacted. Logout revokes the submitted refresh token; access tokens expire normally. Password changes/reset and deletion revoke active access through token-version/account checks; connected clients must close their own sockets on logout.

## Exact commands

From the repository root, at start and finish:

```powershell
python code/server/scripts/verify_client_unchanged.py
```

Initial PowerShell snapshot enumerated every file under `code/client` using `Get-ChildItem -Recurse -Force -File` and `Get-FileHash -Algorithm SHA256`. The final Python comparison enumerated all files, compared the union of relative paths and SHA-256 values, and asserted no differences. Raw snapshots/results are retained in `code/server/.verification/client_snapshot_before.json`, `client_snapshot_after.json`, and `client_hash_result.json`.

From `code/server` (explicit interpreter selects the isolated environment):

```powershell
.\.venv-verify\Scripts\python.exe -m pip install -r requirements-dev.txt
.\.venv-verify\Scripts\python.exe -m pip check
.\.venv-verify\Scripts\python.exe -m ruff check app migrations tests scripts
.\.venv-verify\Scripts\python.exe -m compileall -q app migrations tests scripts
.\.venv-verify\Scripts\python.exe -m pytest -q --tb=short
```

Disposable PostgreSQL 18 cluster creation/start (separate from the user's running service):

```powershell
& 'C:/Program Files/PostgreSQL/18/bin/initdb.exe' -D 'D:/GitHubProjects/Wanderville/code/server/.verification/postgres' -U verifier -A trust --no-locale -E UTF8
& 'C:/Program Files/PostgreSQL/18/bin/pg_ctl.exe' -D 'D:/GitHubProjects/Wanderville/code/server/.verification/postgres' -l 'D:/GitHubProjects/Wanderville/code/server/.verification/postgres.log' -o '-h 127.0.0.1 -p 55439' -w start
& 'C:/Program Files/PostgreSQL/18/bin/createdb.exe' -h 127.0.0.1 -p 55439 -U verifier wanderville_verify_test
$env:WANDERVILLE_TEST_DATABASE_URL='postgresql+psycopg2://verifier@127.0.0.1:55439/wanderville_verify_test'
$env:WANDERVILLE_ALLOW_TEST_RESET='1'
.\.venv-verify\Scripts\python.exe -m pytest -q --tb=short
```

The cluster is localhost-only and disposable; its trust auth is a local verification setting, not deployment guidance. No normal `.env` connection was used for database operations. Test env values were confined to subprocesses.

Final live smoke (requires a newly created empty DB):

```powershell
& 'C:/Program Files/PostgreSQL/18/bin/createdb.exe' -h 127.0.0.1 -p 55439 -U verifier wanderville_smoke_final_test
$env:WANDERVILLE_SMOKE_DATABASE_URL='postgresql+psycopg2://verifier@127.0.0.1:55439/wanderville_smoke_final_test'
.\.venv-verify\Scripts\python.exe scripts/smoke_backend.py
```

Harness starts `python -m uvicorn app.main:app --host 127.0.0.1 --port 58039 --no-access-log` and `python -m app.modules.world.worker` as separate hidden processes, then terminates both. Accounts are verified using a test mailbox without SMTP. Random credentials/tokens are never printed or written to the report/logs. Machine-readable evidence is `.verification/smoke_results.json`; final suites are `.verification/sqlite_final.txt` and `.verification/postgres_final.txt`.

Offline SQL used `DATABASE_URL` pointing only to the disposable PostgreSQL cluster and `WANDERVILLE_ENV=test`, then `python -m alembic upgrade head --sql`. The resulting 0004-inclusive SQL was copied to the documentation export. It contains no credentials.

## Remaining boundaries / configuration

- No backend test remains skipped on PostgreSQL. Godot end-to-end play, full TileSet/building physics, production load/latency/EXPLAIN measurements, real Google OAuth and real SMTP delivery were not run. New UI/rendering and gameplay request wiring remain client-only, with exact mappings in `BACKEND_INTEGRATION_CHECKLIST.md`.
- Original external SRS/design CSV/PDF files were absent from this checkout. The supplied backend guide/audit/remaining-features/API references were read; their original-document interpretation cannot be independently rechecked here.
- Configure production PostgreSQL, a random JWT secret, explicit CORS, real Google client ID (if needed), and HTTPS/STARTTLS SMTP separately. Keep inventory consumption enabled and arbitrary development awards/world mutation disabled. Start the world worker separately from API processes. Existing documented balancing/geometry/retention/pagination limits still apply.
- The temporary verification cluster was stopped after testing. Its data and evidence remain excluded under `.verification/`; the user's original PostgreSQL service was not stopped or modified.
