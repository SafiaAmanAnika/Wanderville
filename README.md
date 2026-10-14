# Wanderville

The existing Godot 4.6 game is connected to the Python/PostgreSQL backend. This checkout now includes the requested world HUD, social/realtime integration, browser Google sign-in, verification/reset email support, and a free-tier deployment blueprint.

- **Start/configure/deploy:** [exact Google, email, database and hosting steps](docs/SETUP_AND_HOSTING.md).
- **Tests, changed files and limitations:** [verification report](docs/VERIFICATION_RESULTS.md).
- **Native Godot proximity text/voice, gifts and wishlists:** [standalone client, setup and protocol](docs/PROXIMITY_BACKEND.md).

## In-game controls

The screen-fixed top-right icons open **Social (globe)**, **Notifications (bell)**, **Inventory (bag)**, **Settings (gear)**, and **Store (shopfront)**. Click again, press Escape, or click outside to close. Only one main panel opens at a time. Settings reuses the existing volume/preferences controls and logout confirmation. Failed saves remain visible and can be retried.

Social contains Nearby/Private chat and Friends, including username search, incoming requests, online status, remove/block/unblock. Closing it preserves conversation drafts; logout clears account data. Remote players reuse the supplied character scene without local input/camera control. Private messages are fetched for the active conversation every two seconds; badges only represent messages actually received plus real friend-request counts.

Inventory shows server-backed stacks, selected-item details, category filters and occupied slots against one shared capacity. Partial stacks fill before new slots are used; changing categories does not change capacity. Supplied crop-frame icons distinguish seeds and produce; missing artwork uses the existing slot placeholder. Notifications paginate and mark only the selected/viewed entry read. The HUD shows level/title, progress to the next level and Aura, with a brief notification when a gameplay action raises the level.

The existing **E** farming interaction, **Q** water collection and **K** crop relocation remain connected to server validation and persistence. The same wooden seed picker supplies the planting flow, shows only owned seeds with season/level restrictions, and links to the Store. Cancelling does not plant or spend inventory.

The wooden Store uses existing server prices and stock; choose Buy or Sell, select an item and quantity, review the total, then confirm. Level restrictions, planting seasons and ownership are separate. Transactions refresh inventory, seed availability, Aura, XP and capacity together. Interrupted transactions retain their request ID across restarts; reopening the store checks the receipt before allowing another transaction. Use Refresh or Retry the same transaction if confirmation is unavailable.

**Claim starter seeds (once)** adds 5 Paddy Seeds and 5 Wheat Seeds, both usable at level one in every season, without resetting existing items or balances. The durable grant marker is retained for accounts that claimed the earlier pack; consuming seeds or logging in never grants it again. All 20 recovered seed types remain in the catalog, with supported level and season restrictions. See the [catalog and verification report](docs/VERIFICATION_RESULTS.md) and [progression rules](docs/SETUP_AND_HOSTING.md#6-progression-and-inventory-rules) for unlocks and rewards. Apply migration `0006_progression_and_stacks` and reference seeding using the [local startup commands](docs/SETUP_AND_HOSTING.md#5-local-startup-and-existing-local-database).

The nine supplied crop scenes retain one-watering continuous growth: ordinary five-frame crops reach harvest at 18 seconds; the six-frame potato reaches it at 22 seconds, following the existing frame durations. The bucket holds 20 and refills one unit per action. Existing server season/level restrictions remain enforced. No starter seeds or invented balances are granted locally.

Day/night tint and existing weather effects are now attached to the world. The authoritative defaults are a **40-minute day/night cycle** (30-minute day/10-minute night) and **7 real days per season**. Seasons do not repaint the map's terrain. These durations come from the existing server rules.

Maps, TileSets, collision geometry, coordinates, character/crop assets and gameplay animations were preserved. Small UI scenes and world attachment nodes were added/updated. The existing map still has invalid atlas-entry warnings; see the verification report's rendering limitations.

On 5 October 2026, after explicit authorization, the **local** database was backed up, migrated to `0006_progression_and_stacks` and seeded; the API passed `/health` and `/ready`. No cloud resources or credentials were changed. Once a shared public API is configured into the exported game, friends need no database installation or database credentials.
