# Campus spawn repair â€” 24 October 2026

The screenshot showed a character beyond the eastern fence because world.tscn used the new scaled map2 scene while the backend still spawned at (7377,-891) and validated movement against map.tscn geometry. Moving only the scene player could not survive the first authoritative snapshot.

The world now spawns at global (1900,500), on clear ground inside the fence. Map scale remains (15,15). The backend and client share generated world-space polygons and spawn data. Run `code/server/.venv312/Scripts/python.exe code/server/scripts/export_campus_geometry.py` after changing the map or world transform; `--check` detects stale data.

Reconnect repairs obsolete campus positions while preserving valid positions. Legacy default farm entrances resolve to the new spawn without modifying farm ownership or saved plots. Backend movement checks enforce the current border and walls. The optional ENet collision world uses the same polygons and verifies the live map transform. Selectable characters no longer freeze solely because the WebSocket disconnects.

The pond retains its solid StaticBody2D banks and now uses a separate Area2D sensor with initialized prompts; the previous script could not attach to the static body. Server water proximity uses the same pond geometry and reach.

Validation: 66 targeted backend tests passed; eight real-map rendered checks passed (spawn parity, fence interior, preserved map scale, dedicated-server collision/spawn parity, physical clearance, pond initialization, selectable-character movement during disconnect). Recursive script/UI load check passed. Broader gameplay suite: 208 passed (voice media/bandwidth/Opus benchmarks excluded). Final script-load check passed after switching the layout to an explicit export resource dependency. Two-client real HTTP/WebSocket integration: Alice and Bob both finished with zero failures (logs: code/server/.verification/client_3cb68d15/). The movement assertion now reads the current spawn; the farm-return assertion waits for asynchronous room confirmation. Existing ObjectDB shutdown leak warnings remain.

Existing missing named building sprites (cds/audi/library), texture UID fallback warnings, and compatibility-renderer particle-trail warnings remain. This repair does not invent building locations or change their artwork. Only the existing HUD routes remain available for those destinations until building hotspots are mapped.

Hosting must run the updated backend and matching client. Restart the backend after updating; an old remote API will still send the retired coordinates. No live account data was edited and nothing was pushed.

## Movement and Google sign-in follow-up

Movement keeps at most two unacknowledged position updates, preserving the five-per-second send budget while avoiding strict one-round-trip pacing. A retained small local lead is published after reconnect. A rejected movement explicitly restores the authoritative position even below the 400-unit reconnect threshold, avoiding repeated rejected moves from an invalid local position. Indoor pause still prevents teleports. Seven synchronization regression checks passed.

Google verification now allows 30 seconds of clock skew, still verifies signature, audience, verified email and browser nonce, and reports actionable clock/client-ID errors. Google failures do not mark username/password fields as incorrect. 91 auth and affected gameplay tests passed. The screenshot alone does not establish the original host-side reason; it requires a fresh attempt against the updated host and, if still failing, its sanitized error log.

A targeted commit includes these fixes and the campus repair, while unrelated local lobby, generated character art and customization changes remain uncommitted. Rebuild/update both clients and restart the updated hosting API before testing with friends.
