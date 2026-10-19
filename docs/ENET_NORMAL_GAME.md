# Experimental ENet movement in the normal game

ENet is opt-in. With GODOT_ENET_GAMEPLAY unset, the normal game keeps its existing WebSocket movement and remote players. No project setting or map resource is changed.

The world character spawner attaches EnetGameplayBridge after selecting the existing character. MovementClient adopts that body, retains its camera, and is the only movement controller. The WebSocket connection still supplies gameplay state, chat, inventory, XP, and other existing service calls; its movement writes and remote avatar renderer are suppressed in this mode.

The dedicated server must also use GODOT_ENET_GAMEPLAY=1 and GODOT_MOVEMENT_ENABLED=1. This mode uses the normal world's map offset and character dimensions. The client checks the server's harvested campus fingerprint and gameplay mode before starting prediction. It reads the already loaded Map node; it does not instantiate a second map or a client-side MovementAuthority.

The client body keeps collision layer 1 (the world layer) in addition to the player layer. The normal game's interaction areas -- water, fishing, the sign board, the farm zone -- all use Godot's default mask of layer 1, so a body that only occupied the player layer would move correctly while no prompt or menu ever opened.

ENet remains a fallback-safe experiment. If admission is rejected or times out, the campus fingerprint disagrees, the authoritative WebSocket room leaves the campus, or the player is already standing in another player's farm, the bridge restores the body, its collision, and the map's tile collision exactly as it found them, re-enables WebSocket movement, and re-enables the standard remote-avatar renderer. There is no state in which the player is left standing on a body whose own controller was switched off.

## Safe local two-client launcher (PowerShell)

From the repository root:

~~~powershell
Set-Location D:\GitHubProjects\Wanderville
$env:GODOT_EXE = 'E:\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64.exe'
$env:PG_BIN = 'C:\Program Files\PostgreSQL\18\bin'
.\code\server\.venv312\Scripts\python.exe code/server/scripts/verify_enet_gameplay.py --manual 300
~~~

This creates a disposable PostgreSQL cluster on a free loopback port, starts an isolated FastAPI service and ENet server, signs in two test accounts, and opens two normal world.tscn game windows with different characters. It stops the processes it owns and the disposable cluster on completion. It never reads the real database connection. The launcher uses isolated Godot user directories; production account saves are not replaced. The test login driver is separate from production gameplay and never runs during a regular launch.

Use arrow keys in each window. Check that the other character moves, idle/run animations change, opening a menu blocks movement, and the camera stays with the local character. Close one window and confirm its avatar disappears in the other. The automated test exercises reconnects; manual windows are bounded to the requested lifetime.

## Automated verification

~~~powershell
.\code\server\.venv312\Scripts\python.exe code/server/scripts/verify_enet_gameplay.py
~~~

The focused checks cover two rendered normal worlds, distinct identities, both character families, server correction of local divergence, remote movement, original camera/HUD/map nodes, menu blocking, duplicate prevention, reconnects, incompatible map rejection, and default legacy movement. Logs, screenshots, and disposable database files remain under test-output/enet-gameplay-* for review.

For an already configured isolated test backend and matching dedicated server, launch the regular game/login flow with:

~~~powershell
$env:WANDERVILLE_API_URL = 'http://127.0.0.1:8123' # your isolated test API port
$env:GODOT_ENET_GAMEPLAY = '1'
$env:GODOT_MULTIPLAYER_HOST = '127.0.0.1'
$env:GODOT_MULTIPLAYER_PORT = '24567'
& $env:GODOT_EXE --path code/client
~~~

The regular game uses the logged-in Global session to request admission tickets. It does not require TEST_TOKEN. To return to legacy mode for subsequently launched clients:

~~~powershell
Remove-Item Env:GODOT_ENET_GAMEPLAY -ErrorAction SilentlyContinue
~~~

## Scope and limitations

- Local/trusted networks only. ENet UDP is plaintext. Use the existing HTTPS/WSS transport for internet deployment.
- Campus movement only. ENet does not implement private farm/house rooms. While a player is on the campus, the dedicated server publishes its authoritative positions to the Python presence layer over a private host-authenticated endpoint (`POST /internal/multiplayer/presence`), so roster, proximity, chat and voice all see where an ENet player actually is rather than the spawn the presence row was committed with. A player in a farm or house (a visiting player) is not bridged: the server neither simulates nor accepts those rooms, so the bridge hands movement back to the standard path instead (see below). Position projection is in-memory only; ENet still does not persist live positions to `player_presence`.
- Shared collision currently contains the existing static campus geometry, not TileSet collision. In experimental mode only, the normal map's TileMapLayer physics is disabled at runtime so prediction matches the dedicated server. Static campus buildings, borders, and lakes remain collidable. Map and TileSet resources are untouched.
- The normal game's camera is retained; the demo's 3x zoom is not applied to it. Characters keep their normal world sizes, with forward playback, 10 FPS run and 6 FPS idle where those animations exist.
- Reconnection returns the player to a server-selected spawn. Persisted ENet world positions are not implemented.
- The pre-existing orange TileSet/art region remains unchanged. The test driver suppresses the known resource-load error flood only while loading the packed world; runtime script errors remain enabled and fail the tests.
- Loading backend state is not end-to-end verification of farming, inventory, XP, or social UI workflows. Report separately any backend regressions and interactions actually exercised.

## Changed code

- `Scripts/character_spawner.gd` attaches `Scripts/network/EnetGameplayBridge.gd` only for explicit opt-in; `Scripts/player.gd` retains the legacy controller, and `Scripts/chara_player.gd` exposes its existing action/fishing input gate.
- `Scripts/network/EnetGameplayBridge.gd` owns the body only for the campus, keeps the world collision layer so interactions still fire, and on any failure restores the body, tile collision and the legacy connection before handing movement back. `Scripts/remote_players.gd` gains an `activate()` path so the standard remote avatars can be switched back on at runtime.
- `Scripts/network/MovementClient.gd` adopts the existing body, waits for server spawn, reconciles against server positions, and resets remote state on reconnect. `RemoteAvatar.gd` and `CharacterPresentation.gd` apply normal-world sizes and animation timing.
- `autoloads/RealtimeClient.gd` suppresses WebSocket movement while the adapter owns positions. `Scripts/remote_players.gd` suppresses duplicate WebSocket avatars.
- `Scripts/network/NetworkLink.gd`, `MovementAuthority.gd`, and `CampusCollision.gd` exchange the campus version and match the production map offset/character sizes. Gameplay authority uses the source geometry even if an old collision cache is configured. No second client map or authoritative client simulation is created.
- `Scripts/network/MovementAuthority.gd` publishes live campus positions to the backend through `Scripts/network/BackendBridge.gd` at 5 Hz (and drops a player immediately on disconnect), which is the same host-authenticated `BackendBridge` that consumes admission tickets.
- `DedicatedServer.gd` defaults to a loopback bind and warns when told to bind a public address, because ENet is plaintext. `Scripts/network/MultiplayerClient.gd` cleans up reconnect/disconnect state safely.
- `app/modules/realtime/internal_router.py` exposes the host-only `POST /internal/multiplayer/presence`; `service.py` overlays a live projection coordinate onto the authorised roster only when the room and epoch match.
- `tests/enet_gameplay.gd`, server `tests/integration/test_enet_gameplay.py`, and `scripts/verify_enet_gameplay.py` provide real-world verification and the disposable local launcher.

## Verification results

- Final ENet checks: **3 passed** (226.99 seconds), re-run after the fallback, collision-layer and presence-bridge changes. Includes two rendered Windows clients running `res://Scenes/world.tscn`, the incompatible-campus rejection (which also asserts the rejected client sent no movement inputs), and the default legacy path. The rendered clients reported zero failures, distinct player IDs, correct movement/remote visibility, forward 10 FPS run animation, authoritative correction, menu blocking, reconnect without duplicate avatars, and clean shutdown; the headless server log showed no presence-bridge or script errors.
- Evidence: `test-output/enet-gameplay-dab75cd5/`. The earlier legacy-default pass is in `test-output/enet-gameplay-run3.log`; that run also caught the shutdown bug fixed before the earlier final ENet rerun.
- Focused regressions: **53 passed** (92.44 seconds): admission tickets, forged identity/invalid movement inputs, farm-entry contract, legacy collision rejection, realtime traffic, farming plant validation/consumption/XP/ownership, and inventory stack removal/isolation. These are backend/API checks, not farming or social UI certification.
- Default normal-world WebSocket test passed: no ENet bridge, WebSocket connection established, and existing controller movement worked.
- Godot script/scene load check: `CLIENT_LOAD_CHECK failures=0`.
- Presence-bridge and roster-overlay checks: the gameplay suite is **202 passed** (`tests/gameplay`), including 7 new focused tests in `tests/gameplay/test_enet_presence_bridge.py` covering host-only access, campus-only acceptance, live-coordinate overlay for the viewer and the caller, leave handling, and the untouched durable row. `ruff check` is clean on every changed Python module.

Reproduce the focused regressions against another disposable database:

~~~powershell
.\code\server\.venv312\Scripts\python.exe code/server/scripts/verify_enet_gameplay.py tests/integration/test_multiplayer_admission.py tests/integration/test_multiplayer_movement.py::test_forged_identity_field_is_rejected tests/integration/test_multiplayer_movement.py::test_invalid_direction_is_rejected tests/gameplay/test_enter_world_contract.py tests/gameplay/test_validation.py::test_known_collision_polygon_rejects_move tests/gameplay/test_realtime_traffic.py tests/farming/test_farming.py::test_plant_validation_consumption_xp_and_ownership tests/inventory/test_inventory.py::test_stacks_removal_and_isolation
~~~
