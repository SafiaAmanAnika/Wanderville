# World, Social Lobby and character room

Use the existing scenes; do not recreate backgrounds or collisions.

| Scene | Required setup | Entry / exit |
|---|---|---|
| world.tscn | Root character_spawner.gd, existing girl player/camera, existing map and HUD | Click Audi for Social Lobby; Library for customization. HUD Social also opens lobby. |
| SocialLobby.tscn | social_lobby.gd root, PlayerSpawn, Camera2D, StaticCollisions, LobbyInteractions instance, Receptionist AnimatedSprite2D | E near reception searches actual users; boards open friends/requests. Bottom E Leave returns to world and its entry position. |
| CustomizationLobby.tscn | customization_lobby.gd root, PlayerSpawn, Camera2D, StaticCollisions, CustomizationInteractions instance | Mirror/wardrobe/appearance open original six-character selector. Explicit Save applies selection. Escape discards. Bottom E Leave returns to world, or character selection when entered from menus. |

Both lobby roots share lobby_player_spawner.gd. Do not add another player instance: the root spawns Global.selected_character and binds the camera. Keep camera limits and existing collision shapes. SceneManager, Global, APIClient and GameState must remain the existing project autoloads.

Private messages use the existing social API. In lobby open Friends and choose Message; Messages shows that conversation. Search and messaging require a real authenticated session. Lobby polls existing direct-message history because campus proximity WebSocket presence is not running in this room. Nearby chat remains a world feature; no shared multiplayer lobby presence is implemented by these local scene routes.

No extra PNGs or new scene instances need to be placed manually. To move an entrance, edit the existing scene's PlayerSpawn marker. To relocate campus routes, edit DESTINATIONS in Scripts/social/lobby_entrance.gd to existing building node names. Keep the original six Assets/charas folders intact.
