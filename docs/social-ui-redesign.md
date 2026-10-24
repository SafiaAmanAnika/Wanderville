# Social and character UI redesign

The UI now follows the shared maroon, walnut, cream and sage palette. The existing API clients, movement authority, room transitions and inventory service remain the owners of their respective operations.

## Implemented screens

- **World HUD:** progress at the top left, Social Lobby and Settings at the top right, a persistent Nearby pill at the bottom left, and Voice at the bottom right. Inventory remains at CDS. Its click target now supports the painted `long_five_arch_hall.png` tiles in the current campus as well as the older named CDS sprite. Settings temporarily hides Nearby, and modal guards prevent opening another gameplay panel over it.
- **Physical Social Lobby:** Reception, Friends, Requests, Farm Visits, Notices and the existing exit are discoverable interaction points. Walking into range shows the interaction hint; only E or an explicit nearby click opens a feature. The existing room art and solid collisions are retained. The duplicate Wardrobe station has been removed; customization stays in its existing separate destination, accessed through the library. Room characters now use 0.72 scale, matching the receptionist, independently of the much larger world artwork.
- **Social window:** a shared responsive 1100 x 720 modal with sidebar navigation, section content and player details. Requests have Incoming/Sent tabs. Player selection is independent of Accept/Decline. Refresh, empty/loading/error states and the existing server-confirmed actions are retained. Messages include a conversation picker; Farm Visits exposes current visitors or Leave Farm. Gifts/wishlists are accessed from Social and use the existing themed gift owner.
- **Nearby:** a compact player list with distance and voice eligibility, nearby chat and Join Voice. Selecting a player reveals profile information, Add Friend, individual mute, Block and Report. Presence updates never expand it. Gifts and full private messaging no longer live here.
- **Voice:** a separate compact view with Not joined/Connecting/Connected states, input and received-audio meters, explicit Join/Leave, Push to Talk (V) by default, optional Open Mic, Mute, Deafen and device selectors. Capture starts only after the user's speaking action. Transmitting is derived from actual captured samples and successful audio sends. A gameplay connection cannot overwrite the voice state. Leaving the room/account or losing the transport releases capture; stale join replies cannot reopen a closed session.
- **Character editor:** one underlying six-preset editor serves first-time selection, Wardrobe Save/Cancel, and read-only Mirror. One large preview animates; six static portraits form a 3-by-2 grid. Direction, Idle/Walk/Run, pause/play and frame stepping are available. Appearance layer tabs are hidden. See [onboarding details](onboarding-ui.md).

## Validation and review

The rendered review uses isolated UI fixtures for social visual states, not production player data. Their plain green background is only a test fixture. The gallery's World view now shows the actual original `world.tscn`/`map2.tscn`, and the separate landing gallery includes the actual CDS inventory. Actual Godot captures are in `test-output/ui-redesign`; [open the gallery](../test-output/ui-redesign/review.html). Full-size and 960 x 640 Social layouts were checked, along with modal exclusivity and draft cancellation.

The two-account integration suite passed through the redesigned controls: username search, sending a friend request, accepting it, removing the resolved request, selecting a private conversation, and exchanging a message. Proximity chat, native Opus negotiation, synthetic PCM playback, silence suppression, gift confirmation/recovery/claim and disconnect cleanup also passed. Those disposable service artifacts are in `code/server/.verification/client_129bcb22`.

Existing character, lobby-interaction, customization and Nearby checks are maintained against the new layouts. The client load check retains the unrelated authentication scene's duplicate `VBox` unique-name warning.

The real-backend HUD suite also passed, including Settings open/save/close, notification actions, inventory/economy flows, maximum-level display and a new-process persistence check. Its disposable artifacts are in `code/server/.verification/client_06f68b92`.

Voice verification used synthetic audio, with capture off when joining. Physical microphones, OS permissions and cross-computer networking still require a hardware test. The current server supplies voice eligibility and mixed room audio, so Nearby shows truthful eligibility rather than inventing per-person speaking meters or individual gain controls.
