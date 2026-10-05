# Gameplay integration verification — 5 October 2026

This update finishes the connected inventory, seed picker, Store, farming rewards and ten-level progression in the existing Godot project. It builds on the original integration and seed/store restoration already present in this checkout. The configured player database and credentials are outside the test scope; migrations are provided separately in the [setup guide](SETUP_AND_HOSTING.md#5-local-startup-and-existing-local-database).

## Catalog and assets

The recovered source remains `b310eae:code/client/autoloads/GameState.gd`, whose later, complete inventory lists these 20 types. Every name maps to `<name>_seed` in inventory and `<name>` as harvested produce:

| Recovered types | Access |
| --- | --- |
| paddy, wheat | Level 1, all seasons |
| sugarcane | Level 2, all seasons |
| sweet_corn, bell_pepper, green_bean, pumpkin, apple, turnip, potato, carrot, cabbage, strawberry, lettuce, pea, radish | Level 4; each keeps its existing season |
| moonflower, rivermint, sunbloom, ancient_grain | Level 8, all seasons; rotating store availability |

The earlier `49142eb` inventory included wheat/corn/cotton/tulip. Existing backend Corn/Cotton remain available at level 2 in summer; Tulip has no matching active crop definition and was not added. No broader concept-PDF catalog was invented.

`WoodPanel.item_icon` explicitly maps Paddy, Wheat, Sugarcane, Sweet Corn, Bell Pepper, Green Bean, Pumpkin, Turnip and Potato to their existing crop scenes. Seeds use the initial SpriteFrames image; produce uses the final image. In particular, canonical `sweet_corn` uses the supplied scene rather than guessing a `sweetcorn` filename. Remaining types use one existing inventory-slot placeholder with the correct label. Original textures and growth frames are retained.

Available scene/script history contained the backend shop, but no recoverable Godot store scene or interaction. The previous restoration therefore added the authorized compact wooden panel; this update extends that same panel. Open it through the **shopfront HUD button** or **Open store** in the existing seed picker. The globe remains Social; Settings retains logout.

## Rules and player flow

- **Inventory:** category filters organize actual stacks and show one shared occupied/capacity counter. Selection exposes the name, stack quantity and relevant item metadata. Matching additions fill partial stacks before consuming another slot.
- **Seed picker:** displays owned seed totals, separate level/season restrictions, existing artwork and a selected state. Cancellation preserves the pending tile without consuming a seed. The existing farming controller sends planting to the server and refreshes state after acceptance.
- **Store:** Buy/Sell retain existing prices, stock and request IDs. Review the chosen quantity and Aura total before confirming. Changes refresh inventory, picker counts, balance and XP/capacity. Lost responses reconcile through saved receipts; retry uses the original ID, including after restart.
- **Progression:** persistent level/title/XP/Aura HUD, within-level progress, maximum-level state and brief level-up feedback. The server defines thresholds, supported unlocks and awards. No missing factories, forest maps or land expansions are announced.
- **Starter:** explicitly claim **5 Paddy Seeds + 5 Wheat Seeds once**, both level-one/all-season, occupying two stacks. Earlier `original_seeds_v1` claims remain claimed; existing items and balances are never replaced or replenished.

The [progression reference](SETUP_AND_HOSTING.md#6-progression-and-inventory-rules) contains all ten thresholds, exact capacity and legacy migration policy, XP awards and item unlocks. New balance choices are **1 planting XP**, **25 Aura at level 2**, **100 Aura at level 10**, and the basic starter quantities above. Harvest XP is **5/10/20/30** for common/seasonal/rare/magical crops plus **15 once per species**. Eligible produced/collected units sell for **5 XP each**; seeds/tools do not grant sale XP. Existing fishing and house-service awards remain connected without adding new gameplay systems.

## Fresh verification

Results below must come from this progression implementation, not prior logs. Disposable databases and isolated Godot user directories are used.

| Check | Current result |
| --- | --- |
| Complete backend suite on disposable PostgreSQL | **225 passed**, one dependency deprecation warning, 143.23 seconds; `postgres_8abf679a/test-result.txt`. Cluster shutdown confirmed |
| Migration preservation, threshold boundaries, multi-level jumps and concurrency | Included in the full PostgreSQL run; **17 additional SQLite migration/inventory checks passed** after the stable stack-ordering fix |
| Godot script/UI scene load | **0 failures**, Godot 4.6.2; existing signup duplicate unique-name warning remains |
| Actual rendered HUD, inventory, picker, Store and restart checks | **76 UI/gameplay checks + 6 separate-process restart checks passed**, fixture `client_22aea53b`; both processes exited 0. Screenshots at 800×600 inspected |
| Python quality and Git whitespace | Ruff on application, tests, verification runner and new migrations passed; Git whitespace check passed |
| Protected maps, geometry and supplied artwork diff | Empty. `map.tscn` matches HEAD; all three serialized terrain tile layers match pre-integration `b310eae`; no missing map resource paths |

Backend tests cover every threshold below/at/above, level-ten persistence, once-only rewards/first harvest, multi-stack additions and full-capacity rollback, sale eligibility/replay, starter compatibility and route contracts. Rendered checks use the actual HUD, picker, store and farming controller with a lightweight background and FarmLayer in a disposable fixture, not the full map. They exercise crop growth using the unchanged scene timing, harvesting, selling, buying replacement seeds, authoritative level/title/progress, multi-level rewards, category filters and restarting in a separate Godot process.

The fixture can substitute HTTP 503 after a committed purchase to verify receipt reconciliation. It also checks a local pending-receipt file that cannot be cleared and a full inventory that still has room inside an existing stack. Fault routes and artificial XP/inventory setup exist only in the runner's generated disposable server. Existing daily-login and harvest-achievement Aura are preserved; balance assertions measure each action's delta so these rewards are accounted for.

The intentional unavailable-server settings test produces a connection warning; the UI run also reports an ObjectDB cleanup warning at exit. Neither produced a failed assertion. Store day rollover refresh was reviewed in code and passed script loading; the test does not wait through a whole 40-minute game day. All disposable backend processes and the PostgreSQL cluster were shut down.

## Files and activation

| Area | Existing files extended / necessary additions |
| --- | --- |
| Shared rules/catalog | Server `app/core/progression.py`, `app/core/config.py`, `app/db/catalog.json`, `app/db/gameplay_seed.py` |
| Atomic inventory/XP | Existing economy, inventory, farming, fishing, housing and shop models/services/schemas; model registry/readiness |
| Migration | `migrations/versions/0006_progression_and_stacks.py`; retains the preceding `0005_shop_receipts_and_starter_grants.py` |
| Godot UI/state | Existing `world_hud`, `seed_picker_menu`, `store_panel` scenes/scripts and autoload state/API; shared wooden components/art mappings |
| Verification | Existing server tests, Godot HUD integration and disposable verification runner |
| Guides | README, setup/hosting guide and this report |

Stop the old backend/worker, run `python -m alembic upgrade head`, then `python -m app.db.seed`, and restart. Exact PowerShell commands are in [local startup](SETUP_AND_HOSTING.md#5-local-startup-and-existing-local-database). Reference seeding updates item metadata, never player inventory. This pass does not deploy a public backend, connect email credentials or silently migrate your configured database.

## Remaining boundaries and prior evidence

**Authorized local activation, 5 October:** separately from the disposable tests above, the user requested the database update and startup. A custom-format PostgreSQL backup was created and its archive verified at `code/server/.verification/local_activation_20261005T082631Z/before_migration.dump`. Migrations 0005/0006 and reference seeding completed. Before/after checks across 35 protected tables (excluding the intended level recalculation/new columns and reference-data updates) found no unexpected changes. The local API was restarted with its world worker enabled; `/health` and `/ready` returned HTTP 200. The existing account is active, email-verified and unlocked; read-only inventory, progression and shop service queries passed. No password was changed or end-to-end password login attempted. PostgreSQL remains running on port 5433, API on port 8000; this is not a public deployment.

The prior restoration recorded 165 backend tests plus 51 rendered UI checks and five restart checks; those counts describe the previous code only. The older successful two-client run (`client_ad0afc8f`) covered real HTTP/WebSocket traffic and actual controller/crop scenes. Later full-world reruns failed with Godot native allocation errors; a lightweight rendered HUD stage cannot establish full-map multiplayer stability. Existing invalid atlas-entry warnings and unsupported crop artwork placeholders remain. Original one-watering Inspector timings and world day/night/seasons are preserved.

The last configured-database audit (4 October) found local PostgreSQL at `127.0.0.1:5433`, migration `0004_boolean_defaults`, and an incompletely seeded catalog. That historical read-only check is not evidence of hosting or current readiness. Google/SMTP/Brevo tests mock provider boundaries; live browser sign-in, inbox delivery and a friend's public connection require the user's external setup and remain separate checks.

To reproduce isolated runs from the repository root (PostgreSQL `bin` on PATH):

```powershell
code/server/.venv312/Scripts/python.exe code/server/scripts/verify_integration.py --postgres
code/server/.venv312/Scripts/python.exe code/server/scripts/verify_integration.py --godot 'E:/Downloads/Godot_v4.6.2-stable_win64.exe/Godot_v4.6.2-stable_win64.exe' --hud --render
```

The runner creates independent database/process fixtures and Godot user directories under ignored `code/server/.verification/`; it does not use the configured player's database or auth save. Run full-world multiplayer checks separately with sufficient available memory.
