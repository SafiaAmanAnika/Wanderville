# Wanderville integration update

This is a script-only update for the supplied Wanderville(3) project. It contains 16 updated GDScript files and one new networking script. It contains no scenes, maps, textures, TileSets, animations, or project.godot changes.

## Apply

1. Close Godot and keep a backup of your current scripts.
2. Copy this package's `code` folder into your existing Wanderville root, merging folders and replacing the included `.gd` files. Do not replace the entire client directory. If you have edited these scripts since the supplied archive, merge those edits; the original and updated file hashes are in `docs/changed_files.json`.
3. Start your existing backend from `code/server` using your configured environment: `python -m uvicorn app.main:app --host 127.0.0.1 --port 8000`. The database must already be migrated and seeded as described in your backend guide. Run the existing world worker separately for timed notifications/events.
4. Open your existing `code/client/project.godot` in Godot 4.6 and run the project. No new autoload registration is needed: APIClient creates its networking child itself.

The default API address is `http://127.0.0.1:8000`. For a different host, set `WANDERVILLE_API_URL` before starting Godot. For example in PowerShell:

```powershell
$env:WANDERVILLE_API_URL = "http://127.0.0.1:8000"
```

Launch Godot from that terminal so it inherits the setting. A remote HTTPS backend automatically uses WSS for realtime communication. Backend database credentials stay on the server; do not put them in the Godot client.

## Connected behavior

- Login/session restoration loads server profile, inventory, economy, farm plots and world state. HTTP requests have individual request nodes and timeouts, so simultaneous calls do not collide. Authenticated HTTP requests renew an expired access token and retry once.
- Existing character selection saves the supported female farmer as backend character code `player1`. Confirmation opens the existing world selection screen. World selection saves `campus` and the world ID. Settings saves existing music/effects sliders; logout revokes the refresh token and closes realtime networking.
- The existing E-key farming flow calls till, plant, water and harvest APIs. It applies accepted server state, uses server plot IDs, restores saved plots on world entry and refreshes state periodically. Seed quantities come from `<crop>_seed` inventory records; harvested produce is not displayed as seed inventory.
- Crop growth frames follow server stages. The server requires watering between growth stages. Local animation timing no longer determines whether a logged-in player's crop is ready.
- The existing Q-key water interaction calls the server refill endpoint and displays its result in the existing prompt. The backend bucket capacity is 20 and requires the player's presence to be near a supported water source.
- The existing weather and day/night scripts consume server environment values. Economy values are available in `GameState.economy`; no new currency HUD is added.
- Entering the existing world opens an authenticated WebSocket. It receives nearby snapshots and sends sequenced position updates, including stationary heartbeats. Initial/reconnect snapshots restore the server position. Movement waits for the initial authenticated snapshot. Leaving the world or logging out closes the socket.

## Chat and features with no existing interface

No chat window, remote-player scene, shop menu or other screen was created. Nearby chat and emotes have a working transport. Private messages use HTTP, with optional two-second polling for explicitly watched conversations. Other players' data is available through snapshots; this update does not create/render remote avatars.

Existing or future scripts can use:

```gdscript
APIClient.realtime.send_nearby_chat("Hello")
APIClient.realtime.send_emote("wave")
APIClient.realtime.nearby_message_received.connect(_on_nearby_message)
APIClient.realtime.snapshot_received.connect(_on_snapshot)

var response = await APIClient.send_direct_message(friend_id, "Hello")
APIClient.realtime.watch_conversation(friend_id)
APIClient.realtime.direct_message_received.connect(_on_direct_message)
# Stop fetching when that conversation closes:
APIClient.realtime.unwatch_conversation(friend_id)
```

Private messaging follows the backend's friendship/blocking rules. `APIClient.realtime.players` contains the latest nearby player records. `request_failed` and `GameState.backend_error` expose failures without adding UI.

For backend modules that have no existing controls, `APIClient.authenticated(method, path, body)` is the shared authenticated entry point. For example, `await APIClient.authenticated(HTTPClient.METHOD_GET, "/shop")` fetches the shop catalog. This is callable API access, not a claim that all gameplay screens are integrated.

## Existing limitations

- New accounts use actual server inventory; the previous free local seed dictionary is removed. Obtain seeds using the existing backend shop API or your development setup. This update does not invent starter items or currency rewards.
- Crop relocation has no backend endpoint. The existing relocation key now reports that it is unsupported for logged-in play instead of making an unsaved local move.
- Only nine crop scenes are supplied. Crops lacking scenes retain the original controller's placeholder behavior; no artwork was invented. The original TileSet/map loading warnings were left untouched.
- No moderator UI, full remote-avatar rendering, new feature screens, or Google browser deep-link completion was added. These are outside this script-only integration. Existing username/password login is the tested path.
- Live PostgreSQL concurrency, two interactive game windows, deployment, and full visual gameplay were not verified here.

## Verification

- Godot 4.6 loaded the 17 integration scripts successfully. All 41 GDScript files passed syntax parsing.
- The existing backend gameplay suite passed: 30 tests, one dependency deprecation warning.
- A headless Godot client connected to a real local Uvicorn backend using temporary accounts and disposable SQLite. It passed login, initial data load, simultaneous HTTP requests, token renewal, profile/settings save, WebSocket auth/movement, nearby chat, private chat/history, the actual farming controller's till/plant/water/harvest calls, bucket synchronization, state reload and logout. The test used accelerated crop timing in its disposable fixture only. See `docs/godot_backend_smoke.log`.
- The smoke test exercised the supplied controller's placeholder crop path. Existing animated crop scenes were inspected, but a full visual crop restoration test was not completed.
- All 1,079 non-GDScript client files were byte-compared with the supplied project and are unchanged. All supplied backend source/configuration files are also unchanged. The archive includes only changed/new client scripts and these notes.
