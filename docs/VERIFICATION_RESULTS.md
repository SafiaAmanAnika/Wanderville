# Integration verification — 4 October 2026

This report supersedes the earlier script-only/October 1 reports. Work was done in the existing project and preserved prior uncommitted edits. No existing player database or credentials were changed. Nothing was deployed, committed, pushed, or emailed to another person.

## Results and boundaries

| Check | Result |
| --- | --- |
| Complete backend suite on fresh PostgreSQL 18 | **153 passed, 0 skipped**, one dependency deprecation warning, 108.43 seconds; fixture `postgres_3b425cbf` |
| Final auth/inventory/readiness regressions | **13 passed**, one warning; disposable SQLite. Includes readiness rejection when required item rules are missing |
| Python quality | Ruff, compilation and `pip check` passed |
| Godot script and UI scene load | Godot 4.6.2; **0 failures**. Includes HUD, seed picker, social and auth scenes. An existing duplicate unique `VBox` warning remains in the signup scene |
| Real two-client gameplay run | Fixture `client_ad0afc8f`: **Alice and Bob both exited 0**, all recorded checks passed. Real HTTP/WebSocket traffic, actual world/player/crop/controller scenes; headless, not a visual two-window test |
| Final rendered HUD regression | Fixture `client_d63e8467`: **35 checks passed**, 0 failures, real disposable accounts/API/database. Native OpenGL renderer, supplied avatar artwork, lightweight UI test stage; screenshots at 1578×997 and 800×600 inspected |
| Full-map repeatability | **Not fully verified.** Later two-client reruns failed with Godot native `alloc_static`/`mem_new` allocation errors and signal 11 while loading the existing world. Even a temporary test-only particle reduction did not resolve this; that workaround was removed. Last failure: `client_760103b1` |
| Full rendered multiplayer world | Earlier attempt also failed natively. Do not treat the separate rendered HUD stage as proof that two full rendered game windows are stable |
| Protected content | Git diff confirms no changes to `Assets/`, `Scenes/map.tscn`, `Scenes/crops/`, `Scenes/player1.tscn`, or `Scripts/crop_visual.gd`; no terrain, TileSets, collision geometry, coordinates or supplied animations were edited |

All fixture artifacts are under `code/server/.verification/` (ignored by Git). Disposable processes/clusters were shut down; their files/logs remain for inspection. The final memory check showed about 3 GB physical and 3.4 GB virtual memory available after test cleanup. The native error explicitly reported allocation failure; a definitive engine-level cause was not established. The user's existing Godot/editor process was not terminated. Release memory before repeating the two-client command below. Existing invalid TileSet atlas entries also produce many warnings; their duplicates are suppressed only during resource loading in the test harness, without editing those assets.

## What the checks exercised

The successful two-client run covered login and saved-state loading; coordinated concurrent token refresh; rejection of a stale request after signing back into the same account; authenticated WebSockets; local movement and stationary heartbeats; remote actor creation/interpolation targets; camera/input isolation; nearby filtering and duplicate prevention; friend search/request/accept/online status; private recipient/history delivery; blocking and removal of remote actors; reconnect; typing/input blocking; logout/socket/poll cleanup; and the actual farming controller's planting, one watering, timed visual frames, relocation, world reload, restored crop and harvest.

The final HUD run covered each icon/toggle; one main panel; Escape/outside-click closure and input flags; social drafts across tabs/closing; real inventory quantity, atlas-frame icons, placeholder and selected details; real unread count, 30-item page/cursor, selected-only read and dismissal; settings persistence and a deliberately unavailable-server failure that retains the panel with an error; the existing seed picker's images and cancellation; account cleanup; visible day/night tint; and all four season/precipitation combinations through the real weather attachment scripts. The expected connection warning in this run belongs to the intentional failed-save test.

Tests mock Google token verification/exchange and SMTP/Brevo transport at the external provider boundary. They do **not** prove a live Google browser login or delivery to a real inbox. Those require the user's provider credentials. No sender account was connected automatically.

## Database status

The read-only audit used `SET TRANSACTION READ ONLY` and SELECTs. The configured database is PostgreSQL **18.6**, `wanderville_dev` on **127.0.0.1:5433**, migration **0004_boolean_defaults**, **42 tables**, and **22 item definitions**. This confirms a working local database connection, not public hosting. Fresh complete reference seeding in tests produces 51 definitions; the current local setup still needs its explicit reference-data update.

The existing local API answered `/health` 200. Its `/ready` request timed out during the audit, so that running process was not certified ready. The updated `/ready` implementation passed isolated tests and now rejects missing required gameplay seed rules as well as wrong migration/clock setup. Restart/update the local backend using the setup guide; no running user service was silently restarted.

Google client ID and SMTP credentials were unset; the configured email host was local development SMTP and the sender was a placeholder. No public backend URL was supplied. Consequently, no live cloud database or friend's remote connection has yet been verified.

## Changes, grouped by purpose

| Files | Purpose |
| --- | --- |
| `Scenes/world_hud.tscn`, `Scripts/world_hud.gd` | One editable CanvasLayer HUD with icons, floating inventory/notification panels, authoritative counters and account cleanup |
| `Scenes/social_panel.tscn`, `Scripts/social_panel.gd` | Social panel contained under the globe: nearby/private chat, friends/actions, preserved drafts, bounded history/polling and real received-message badges |
| `Scripts/remote_players.gd` | Reuse supplied character visuals for remote presence; disable local controller/collision/camera and interpolate received motion |
| `Scenes/world.tscn` | Only necessary attachment resources/nodes: WorldHUD, RemotePlayers, DayNight CanvasModulate; existing world nodes/transforms retained |
| `Scenes/seed_picker_menu.tscn`, `Scripts/seed_picker_menu.gd`, `Scripts/components/wood_panel.gd` | Restyle the same seed picker, retain planting signal, add scrolling/restriction labels and supported seed purchases; share explicit artwork mapping/placeholder |
| `Scenes/menus/SettingsOverlay.tscn`, `Scenes/menus/LogoutConfirmationDialog.tscn`, `Scripts/menus/settings_overlay.gd` | Reuse settings in-world, expose save failure, add existing logout confirmation, fit confirmation buttons in smaller windows |
| `autoloads/APIClient.gd`, `GameState.gd`, `Global.gd`, `RealtimeClient.gd` | Browser OAuth/PKCE, safe concurrent HTTP/refresh, session versioning, shared authoritative state/signals, bounded reconnect/history polling and cleanup |
| Existing login/signup/email-verification/main-menu/character/world-selection scripts | Complete existing navigation and profile/auth persistence; accurate development-mail and failure messages |
| `Scripts/farm_controller.gd`, `water_source.gd`, `farm_menu.gd`, `player.gd`, `sign_board.gd` | Preserve existing interaction paths while validating/saving actions, reconciling uncertain responses and blocking gameplay during UI interaction |
| `Scripts/day_and_night_cycle.gd`, `weather_manager.gd`, `weather_fx_manager.gd` | Attach the previously unused day/night/weather behavior, correct seconds, consume server time/seasons and avoid season signals overwriting precipitation |
| Server `modules/auth/{oauth,email,pages,router,schemas,service}.py`, `core/config.py`, `.env.example` | Desktop Google code exchange/nonce verification, browser verification/reset pages, truthful delivery failures, explicit local/Gmail/Brevo delivery |
| Server `modules/farming/{service,router,schemas}.py` | Preserve Inspector growth frames/timing and one-water behavior, refill amount and persistent validated relocation |
| Server `modules/inventory/{service,schemas}.py` | Return existing partition names/counts and configured capacity for the HUD |
| Server `modules/realtime/{router,service}.py`, `modules/social/service.py` | Socket ownership, offline/reconnect position consistency and online status based on live presence |
| Server `main.py`, root `render.yaml` | Database readiness plus opt-in in-process existing worker; free web service with external Neon and HTTPS email |
| Server/client tests, `scripts/verify_integration.py`, `docs/_audit_runtime.py` | Isolated PostgreSQL/API/Godot tests and read-only local status audit; updated contracts and intended farming expectations |
| `scripts/configure_auth.py`, README, setup guide, this report, `.gitignore` | Safe private configuration helper, exact startup/provider steps, current evidence and exclusion of disposable environments/mail/logs |

Godot-generated `.uid` files accompany new scripts. No new migration or replacement map/controller was needed.

## Gameplay decisions and use

- **HUD:** top-right globe/social, bell/notifications, bag/inventory and gear/settings; click again, Escape, or outside to close. Save failures keep settings open. Small windows allow panel scrolling. Logout is in settings and requires the existing confirmation.
- **Farming:** existing E interaction and K relocation continue through the same controller. One watering starts continuous scene growth. Five-frame supplied crops: 5+6+7 = 18 seconds to harvest; potato: 5+6+7+4 = 22 seconds. Inspector artwork/frame sequence is preserved. Season/level restrictions and server inventory still apply. Q adds one water unit up to capacity 20.
- **Time:** day/night is now visibly wired; current authoritative default is 40 real minutes per cycle, with 30 minutes day and 10 minutes night. Seasons advance every **7 real days** under the existing backend defaults. Seasonal particle effects are connected; no seasonal terrain repainting was invented. Weather/timing boundary rules are also covered by backend tests.
- **Data:** XP/level/threshold/Aura are server values. Login progression may award Aura; tests compare the actual server balance, not an invented zero. Harvest/purchase reconciliation refreshes gameplay state. Notification opening does not bulk-mark read.
- **Privacy:** only the active private conversation is polled. The globe badge combines actual pending requests with received unread messages; it is not a promise of a global private-message inbox/read-receipt system.

## Reproduce

From the repository root (PostgreSQL `bin` must be on PATH):

```powershell
code/server/.venv312/Scripts/python.exe code/server/scripts/verify_integration.py --postgres
code/server/.venv312/Scripts/python.exe code/server/scripts/verify_integration.py --godot 'E:/Downloads/Godot_v4.6.2-stable_win64.exe/Godot_v4.6.2-stable_win64.exe'
code/server/.venv312/Scripts/python.exe code/server/scripts/verify_integration.py --godot 'E:/Downloads/Godot_v4.6.2-stable_win64.exe/Godot_v4.6.2-stable_win64.exe' --hud --render
```

Run the two Godot commands separately with sufficient available memory. Each run creates independent fixture data and user directories; it never reuses the existing player's auth file. The PostgreSQL runner initializes a separate loopback cluster rather than using the application's configured database.

For actual startup, Google/Gmail steps, free hosting and friends' configuration, use [SETUP_AND_HOSTING.md](SETUP_AND_HOSTING.md). Remaining external steps are creation/configuration of the provider accounts, deployment, a real Google authorization, an inbox delivery check, and a shared public connection check. Full-map rendered multiplayer stability remains unverified because of the native allocation failures above.
