# Godot client

The scenes, autoloads and scripts to inspect when changing the game.

<details>
<summary><strong>Explore this page</strong></summary>

[Home](../README.md) · [Entry and shared state](#entry-and-shared-state) · [Where to work](#where-to-work) · [UI and persistence](#ui-and-persistence) · [Gameplay systems](#gameplay-systems) · [Housing lifecycle](#housing-lifecycle) · [Fishing lifecycle](#fishing-lifecycle) · [Audio lifecycle](#audio-lifecycle) · [World and room presentation](#world-and-room-presentation) · [Movement modes](#movement-modes)

</details>


## Entry and shared state

The project targets Godot 4.6, uses the compatibility renderer, and opens `Scenes/menus/TitleScreen.tscn`. The viewport is 1578 × 997 with `canvas_items` stretch. Pixel transform snapping is enabled.

| Autoload | Responsibility |
| --- | --- |
| GameState | Shared gameplay state |
| Global | Account/session and shared values |
| SceneManager | Scene transitions |
| APIClient | HTTP calls and backend configuration |
| AudioManager | Audio preferences and playback |
| HousePrompt | Shared house interaction prompt |

These names come from [project.godot](../code/client/project.godot). RealtimeClient exists as a script and is not listed as a project autoload in this revision.

## Where to work

| Area | Source |
| --- | --- |
| Original player input and action gates | [player.gd](../code/client/Scripts/player.gd), [chara_player.gd](../code/client/Scripts/chara_player.gd) |
| Character attachment | [character_spawner.gd](../code/client/Scripts/character_spawner.gd) |
| HTTP integration | [APIClient.gd](../code/client/autoloads/APIClient.gd) |
| Realtime session | [RealtimeClient.gd](../code/client/autoloads/RealtimeClient.gd) |
| Remote players | [remote_players.gd](../code/client/Scripts/remote_players.gd) |
| Optional ENet adapter | [EnetGameplayBridge.gd](../code/client/Scripts/network/EnetGameplayBridge.gd) |

## UI and persistence

The title uses the supplied campus background and botanical logo. The Store refreshes inventory, Aura and XP from server results and retains pending request IDs. Social keeps private chat and friends together; Nearby serves proximity interaction. Server errors should remain visible so users can retry.

Detailed house layouts are saved locally with server/account/world scoping. They should not be described as a server-synchronized furniture system. Inspect the [housing scripts](../code/client/Scripts) before changing key formats or recovering old saves.

## Gameplay systems

| Feature | Client ownership and implementation |
| --- | --- |
| Farm | [farm_controller.gd](../code/client/Scripts/farm_controller.gd) resolves the zone/grid, mouse actions, E carry/drop, requests and tile visuals; [crop_visual.gd](../code/client/Scripts/crop_visual.gd) animates growth |
| Trees | [TreeSeasonManager.gd](../code/client/Scripts/TreeSeasonManager.gd) chooses visible tree groups; [tree_cutter.gd](../code/client/Scripts/trees/tree_cutter.gd) owns reach checks, axe feedback and `/trees` integration |
| Houses | [house_manager.gd](../code/client/Scripts/housing/house_manager.gd) owns placement, staged construction, interior transitions, local saves, selling and destroying |
| Furniture | [furniture_catalog.gd](../code/client/Scripts/furniture/furniture_catalog.gd) loads 228 manifest entries; [furniture_item.gd](../code/client/Scripts/furniture/furniture_item.gd) handles directional art, scale and blockers |
| Fishing | [fishing_game.gd](../code/client/Scripts/fishing_game.gd), [fish.gd](../code/client/Scripts/fish.gd) and [target.gd](../code/client/Scripts/target.gd) implement the moving-target minigame |
| Inventory room | [storage_house.gd](../code/client/Scripts/inventory/storage_house.gd) makes CDS clickable; [storage_menu.gd](../code/client/Scripts/inventory/storage_menu.gd) supplies shelves, slots, aquarium and buy/sell |
| Player marketplace | [marketplace.gd](../code/client/Scripts/marketplace/marketplace.gd), [general_store.gd](../code/client/Scripts/marketplace/general_store.gd) and [shop_window.gd](../code/client/Scripts/marketplace/shop_window.gd) manage plots, stock, prices and sales |
| Pets | [pet_manager.gd](../code/client/Scripts/pets/pet_manager.gd) owns selection; [pet_companion.gd](../code/client/Scripts/pets/pet_companion.gd) and [pet_navigation.gd](../code/client/Scripts/pets/pet_navigation.gd) simulate behavior/navigation |
| Character editor | [creator_panel.gd](../code/client/Scripts/customization/creator_panel.gd) implements first-time, Wardrobe and Mirror modes; [customization_interactions.gd](../code/client/Scripts/customization_interactions.gd) exposes room/profile actions |
| Social rooms | [lobby_entrance.gd](../code/client/Scripts/social/lobby_entrance.gd), [lobby_interactions.gd](../code/client/Scripts/social/lobby_interactions.gd) and [lobby_social_panel.gd](../code/client/Scripts/social/lobby_social_panel.gd) connect buildings, stations, friends and invitations |
| Nearby and gifts | [proximity_social.gd](../code/client/Scripts/social/proximity_social.gd), [proximity_voice.gd](../code/client/Scripts/social/proximity_voice.gd) and [community_window.gd](../code/client/Scripts/social/community_window.gd) implement text/voice, wishlist/gifts and privacy |
| Atmosphere | [seasonal_effects.gd](../code/client/Scripts/seasonal_effects.gd), [day_night_cycle.gd](../code/client/Scripts/day_night_cycle.gd) and [AudioManager.gd](../code/client/autoloads/AudioManager.gd) drive particles, tint and sound |
| Guidance/settings | [onboarding_guide.gd](../code/client/Scripts/ui/onboarding_guide.gd), [world_hud.gd](../code/client/Scripts/world_hud.gd) and [settings_overlay.gd](../code/client/Scripts/menus/settings_overlay.gd) provide hints, rewards/notices, audio preferences and session actions |

## Housing lifecycle

J opens the six-house catalog at the building site. HouseManager moves a ghost on a 32-unit grid, checks placement, and stores `none → outer → walls → done`. H near the exterior door builds/enters the inside. One of `house1.tscn` through `house6.tscn` is instantiated at the catalog's interior position `(60000, 0)`, with an entry spawn and Exit area. A fade covers camera/position changes.

Inside, the floor picker previews five finishes. Completed floors enable the furniture catalog; pieces use four directions, 16-unit positioning, R rotation, I/O scale and S rearrangement. The manager cancels pending placements and disconnects old panels on account/world changes. House data includes design, position, build stage, floor and furniture records.

These layouts use `GameState.house_save_path()`, scoped by API origin, account and owned world. Construction spending currently uses a temporary signed-in wood counter; house sale credit uses the local economy helper. The backend `/housing` tier/decorations records do not replace this client layout. See [exact housing rules](GAME_MECHANICS.md#housing-and-furniture).

## Fishing lifecycle

`chara_player.gd` registers F, checks water proximity, plays the fishing action and instantiates `Scenes/fishing.tscn`. It pauses the local tree while the fishing layer and physics keep processing. The fish and target use a dedicated collision layer, isolated from campus physics.

The minigame selects one of ten species, tracks overlap time and drains/fills a catch meter. Esc, timeout or success closes it through one completion signal. The character resumes input and records the catch through `APIClient.record_catch` when signed in, or local inventory when offline. A catch rejected by the API is shown to the player. [Mechanics](GAME_MECHANICS.md#fishing-minigame) lists the actual timer, step and movement constants.

## Audio lifecycle

AudioManager runs with `PROCESS_MODE_ALWAYS`, so its controls survive the fishing pause. It creates Music/SFX buses, loads `settings.cfg`, manages a 12-voice effect pool and named loops, and automatically wires button click/hover sounds unless a button opts out with `silent` metadata.

The title has its own track; campus, Social Lobby and Customization share the world track; marketplace has a separate theme. Fishing pauses normal music, starts the minigame loop, plays a success/failure effect and resumes the previous music when closed. Action calls cover footsteps, farm work, wood cutting, furniture, pets, chat, notifications, Aura and level-up cues. Settings changes whole-bus volume/mute rather than one isolated AudioStreamPlayer.

## World and room presentation

`character_spawner.gd` adds the inventory-building entrance, marketplace entrance, social/customization entrances, companions and onboarding guide to the world. It also adds/removes WASD direction events for that scene's lifetime. The library, auditorium, CDS storage room and marketplace therefore belong in client maintenance coverage as well as the farm.

SeasonalEffects subscribes to backend world updates when logged in; offline it keeps a local season/rain schedule. TreeSeasonManager switches seasonal tree groups. DayNightCycle independently tints the canvas using its local 25-minute-day/5-minute-night defaults. The server's 40-minute clock is a separate rule; do not assume those timelines are synchronized.

## Movement modes

The ordinary controller uses Godot direction actions. ENet attaches only when explicitly enabled, adopts the existing body and camera, and disables duplicate WebSocket movement/avatars. Failure or leaving supported campus scope restores the standard path. See [networking](NETWORKING.md) for authority and limitations.

Known map/atlas warnings in historical reports remain a visual verification concern; this documentation pass does not certify a clean render of every map or scene.

<details>
<summary><strong>Source and verification</strong></summary>

Source reviewed: `31ca97c39c05` · 2026-11-01. Source inspection is not a new gameplay test.

</details>

[← Previous](SYSTEM_DESIGN.md) · [Back to top](#godot-client) · [Next →](DATABASE.md)
