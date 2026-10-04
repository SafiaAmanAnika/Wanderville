# Wanderville

The existing Godot 4.6 game is connected to the Python/PostgreSQL backend. This checkout now includes the requested world HUD, social/realtime integration, browser Google sign-in, verification/reset email support, and a free-tier deployment blueprint.

- **Start/configure/deploy:** [exact Google, email, database and hosting steps](docs/SETUP_AND_HOSTING.md).
- **Tests, changed files and limitations:** [verification report](docs/VERIFICATION_RESULTS.md).

## In-game controls

The screen-fixed top-right icons open **Social (globe)**, **Notifications (bell)**, **Inventory (bag)**, and **Settings (gear)**. Click again, press Escape, or click outside to close. Only one main panel opens at a time. Settings reuses the existing volume/preferences controls and logout confirmation. Failed saves remain visible and can be retried.

Social contains Nearby/Private chat and Friends, including username search, incoming requests, online status, remove/block/unblock. Closing it preserves conversation drafts; logout clears account data. Remote players reuse the supplied character scene without local input/camera control. Private messages are fetched for the active conversation every two seconds; badges only represent messages actually received plus real friend-request counts.

Inventory displays actual stacks, backend partitions/capacity, descriptions and supplied crop-frame icons; items without artwork use the existing slot image. Notifications paginate and mark only the selected/viewed entry read. XP, level thresholds and Aura come from the server. These panels have no invented equip/sell/discard actions.

The existing **E** farming interaction, **Q** water collection and **K** crop relocation remain connected to server validation and persistence. The same wooden seed picker supplies the planting flow, shows owned seeds/restrictions, and offers the supported seed purchases. Cancelling does not plant or spend inventory.

The nine supplied crop scenes retain one-watering continuous growth: ordinary five-frame crops reach harvest at 18 seconds; the six-frame potato reaches it at 22 seconds, following the existing frame durations. The bucket holds 20 and refills one unit per action. Existing server season/level restrictions remain enforced. No starter seeds or invented balances are granted locally.

Day/night tint and existing weather effects are now attached to the world. The authoritative defaults are a **40-minute day/night cycle** (30-minute day/10-minute night) and **7 real days per season**. Seasons do not repaint the map's terrain. These durations come from the existing server rules.

Maps, TileSets, collision geometry, coordinates, character/crop assets and gameplay animations were preserved. Small UI scenes and world attachment nodes were added/updated. The existing map still has invalid atlas-entry warnings; see the verification report's rendering limitations.

The configured database is currently **local**. No cloud resources were created, no credentials were filled in, and no existing player database was migrated or reset. Once a shared public API is configured into the exported game, friends need no database installation or database credentials.
