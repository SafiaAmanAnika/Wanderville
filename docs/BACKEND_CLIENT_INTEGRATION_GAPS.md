# Client integration gaps

**Backend farming API is ready, but current Godot farming gameplay remains partly
local and therefore cannot be fully synchronized/persisted without future client
integration.** This refactor changes no files under `code/client/**`.

## Observed gaps in the supplied client

| Client location / behavior | Consequence and next integration task |
| --- | --- |
| `Scripts/farm_controller.gd` maintains tilled_tiles, active_crops, local watering, movement and harvesting | The local actions do not call the farm API. Wire till/plant/water/harvest and reconcile accepted server results in a future client task. |
| `autoloads/GameState.gd` fetches farm plots but the reconstruction loop is `pass` | Saved server crops are not rebuilt on the map after login. Add tile/crop reconstruction. |
| GameState owns water_drops, spend_water and add_water | Bucket charges are not persisted. The backend does not fabricate or enforce this missing state. |
| GameState replaces seed_inventory from every returned inventory item | It does not separate seeds from harvested crops. The existing catalog uses one code for each crop. Agree on distinct seed/produce definitions and partitions before wiring them. |
| GameState checks taka_balance and current_season but uses `pass` | Aura and shared season changes are not applied to the gameplay HUD/environment. |
| Client local season/weather and crop animation timers | Server stage progression and seasonal rates do not yet drive visible crop animation. |
| Login scene opens `/auth/google/redirect` | That browser authorization flow was absent in the original backend. POST `/auth/google` is preserved and secured; browser redirect/callback/deep-link handoff still needs implementation and credentials. |
| Global stores refresh_token; APIClient lacks refresh/logout wrappers | Server refresh rotation and logout work, but automatic client renewal/session revocation needs wiring. Password changes invalidate the current session immediately. |
| Global handles verification/reset command-line deep links | OS protocol registration/packaging is external to the backend. Verification can be completed in a browser; reset tokens can be submitted through `/docs`. |
| No position-writing request is present | position_x/y are deprecated zero response fields, not persisted player positions. |

The preserved endpoint paths and JSON shapes make future integration possible;
they do not make local actions automatically authoritative. Server signup starts
with empty inventory. Use the dev-only add endpoint for test seeds, or decide a
server-owned starter allocation before connecting the production game loop.

## Scope remaining from the larger SRS

This task implements and stabilizes the existing six backend domains. It does
not complete all 126 requirements. Distinct inventory partitions/capacities,
sale/shop actions, lifetime harvest statistics, random weather scheduling and
rain-triggered watering, visual environmental effects, movement validation,
decorations, fishing, housing, pets, friendships, gifts/trade escrow, chat,
achievements, tasks, notifications and multiplayer/WebSockets are deferred.
Global weather is stored and returned; no fake weather scheduler is included.

Current backend additions that the client does not call yet include `/farm/till`
and `/economy/transactions`. Arbitrary map JSON endpoints (`/world/tile` and
`/world/tiles`) had no current Godot callers and now return a clear HTTP 410.
The world response retains `tiles: {}` as a compatibility field.

The backend enforces stack limits and positive quantities, but the old catalog's
crop categories are not a complete Seeds/Crops/Fish/Tools/Houses partition model.
Do not describe partition capacity or future gameplay modules as implemented.
