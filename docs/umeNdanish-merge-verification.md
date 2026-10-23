# umeNdanish merge verification â€” 24 October 2026

Merged `origin/umeNdanish` at `5d6b214` into local `diza` in merge commit `c6560ac`. No push was performed. Existing tracked and untracked work was restored after the merge; the pre-merge backup remains in the named Git stash `codex pre-umeNdanish merge 2026-10-24`.

Conflicts resolved in RealtimeClient.gd and project.godot: retained ENet/external movement handling, heartbeat/proximity/voice support, existing API URL and microphone configuration; incorporated the incoming house pause_movement guards. Verification runner commit `c8e81d4` shares Assests_2 with isolated client fixtures and explicitly enables their expected verification-email flow.

## Checks

- Godot 4.6.2 recursive script and selected UI scene loading: zero failures; existing signup duplicate unique-name warning.
- Isolated HUD integration: 62 passing checks, plus 4 passing restart checks. Logs: code/server/.verification/client_f3b516f7/.
- Isolated full-world two-client integration: Alice 37 and Bob 35 passing checks, zero reported assertion failures. Logs: code/server/.verification/client_ad476f50/.
- Backend PostgreSQL suite: incomplete. Progress passed the 66% marker and native voice bandwidth/sound checks without reported assertion failures, then stopped producing output. The pytest process remained at the same CPU time for several minutes and was stopped; its wrapper exited. No complete backend pass is claimed. The exact stalled test was not confirmed.

## Runtime issues found despite passing assertions

- map2.tscn attaches water_source.gd (extends Area2D) to a StaticBody2D WaterSource node. Godot rejects that script; the water interaction is broken on this map. The source also expects PromptLayer children absent from that node. A proper water interaction area and prompt must be restored while preserving the pond collision geometry.
- The new map lacks the named cds, audi and library building sprites expected by storage_house.gd and social/lobby_entrance.gd. Their building-click entrances do not attach. HUD actions remain available where implemented.
- The previously discussed disconnect movement gate and unconditional reconnect position correction remain; the incoming branch does not implement the proposed 400-unit correction threshold.
- These checks ran headlessly. They establish automated behavior, not visual map correctness or manual house/furniture interaction coverage. Existing ObjectDB shutdown leak warnings were also observed.

Player data and credentials were not changed; backend and client integration checks used disposable databases and isolated client save directories.
