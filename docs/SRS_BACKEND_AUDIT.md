# SRS and architecture audit

Sources read: the uploaded `147`-row functional-requirement/user-story CSV, the 14-page software design PDF (including visual class diagrams on pages 5–6 and all five tier diagrams on pages 9–13), the uploaded server source, backend documentation/tests, and read-only client integration code/map geometry.

The CSV contains **126 distinct FR IDs** and **147 user-story rows**. Its status column is a planning snapshot; status below is based on inspected implementation and the delivered update, not copied “Done” values.

## Design interpretation

The class diagram places Player at the center of Farm, Inventory, House, Pet, Friends, Gifts, Tasks and Achievements. Those concepts map to relational entities, but service/manager classes do not each need a database table. GameManager, SaveManager, FishingSystem and SeasonalManager are behavior: they belong in services or the client. Animation state is transient client presentation except short-lived multiplayer emotes/presence.

Several diagram multiplicities are informal (for example friendship/chat cardinalities). The implementation uses one profile/world/house/pet per account, many farm tiles/items/progress/notifications, and one canonical friendship row per unordered pair. Item inheritance is represented by shared item definitions plus item rules; a fish is a catalog item rather than a duplicate inventory identity.

The three tiers remain Godot presentation → authenticated FastAPI logic → SQLAlchemy/PostgreSQL persistence. Database foreign keys, checks and uniqueness enforce integrity even though gameplay decisions remain in services. No client database access is introduced. Transactional persistence replaces a generic SaveSlot blob because inventory, currency and ownership must not be accepted from arbitrary client snapshots.

The uploaded implementation already had auth/session/email/Google support, player worlds, economy/XP, inventory stacks and four-stage seasonal crop growth. It did not already implement the new shop, fishing, housing, pets, progression, social, notification or multiplayer APIs. Current client gaps and missing request mappings are documented in `BACKEND_INTEGRATION_CHECKLIST.md`.

## How to read coverage

- **Backend supported**: a server API, stored state or trusted service action supports this requirement; any related new client screen still needs future wiring.
- **Partial / integration**: a concrete remaining condition is described. Do not mark the whole FR complete.
- **Client responsibility**: primarily rendering/input/packaging; no client work was authorized here.

This is not a claim that all 126 requirements are end-to-end complete.

| FR | User-story titles | Coverage | Domain | Evidence / boundary |
| --- | --- | --- | --- | --- |
| FR_1 | Open game | Client responsibility | auth / profile | Presentation remains in unchanged Godot client. |
| FR_2 | View title screen | Client responsibility | auth / profile | Presentation remains in unchanged Godot client. |
| FR_3 | Create account; Handle duplicate username/email; Handle invalid password format | Backend supported | auth / profile | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_4 | Log in | Backend supported | auth / profile | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_5 | Handle wrong password | Backend supported | auth / profile | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_6 | Stay logged in | Backend supported | auth / profile | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_7 | Log out | Backend supported | auth / profile | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_8 | Select character | Backend supported | profile | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_9 | Select map | Backend supported | profile | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_10 | Resume last selection | Backend supported | profile | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_11 | Enter world | Client responsibility | realtime / world / client | Presentation remains in unchanged Godot client. |
| FR_12 | Move with keys | Partial / integration | realtime / world / client | Sequenced speed-limited server movement; Godot input/diagonal controls unchanged. |
| FR_13 | Blocked by objects | Partial / integration | realtime / world / client | Exported campus collision polygons validated; full TileSet/player-shape physics is not mirrored. |
| FR_14 | Camera follow | Client responsibility | realtime / world / client | Presentation remains in unchanged Godot client. |
| FR_15 | Spawn at main gate | Partial / integration | realtime / world / client | Backend entry uses supplied main-gate coordinates after reconnect grace; client camera/spawn wiring remains. |
| FR_16 | Distinct world areas | Client responsibility | realtime / world / client | Presentation remains in unchanged Godot client. |
| FR_17 | Landmarks on map | Client responsibility | realtime / world / client | Presentation remains in unchanged Godot client. |
| FR_18 | Own farm world | Partial / integration | farming / housing / progression | Existing per-player world retained; pre-tilled starter plots are not automatically generated. |
| FR_19 | Till farm tiles | Backend supported | farming / housing / progression | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_20 | Plant seeds | Backend supported | farming / housing / progression | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_21 | Water crops | Backend supported | farming / housing / progression | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_22 | See growth stages | Backend supported | farming / housing / progression | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_23 | No crop death | Backend supported | farming / housing / progression | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_24 | Harvest crops | Backend supported | farming / housing / progression | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_25 | Refill watering bucket | Backend supported | farming / housing / progression | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_26 | Empty watering bucket warning | Backend supported | farming / housing / progression | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_27 | View lifetime harvest count | Backend supported | farming / housing / progression | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_28 | Place outdoor decorations | Partial / integration | farming / housing / progression | Owned nonblocking decoration records; client drawing/placement UI remains. |
| FR_29 | Season-restricted planting; Out-of-season message | Backend supported | farming / housing / progression | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_30 | Fishing spots | Client responsibility | fishing | Presentation remains in unchanged Godot client. |
| FR_31 | Catch fish | Backend supported | fishing | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_32 | Collect rare materials | Backend supported | fishing | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_33 | Catch to inventory | Partial / integration | fishing | Catch/drop persistence with five-minute expiry; ground rendering and sound remain. |
| FR_34 | Switch fishing rods | Backend supported | fishing | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_35 | Catch rare fishes | Backend supported | fishing | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_36 | Own house | Partial / integration | housing | Starter house row is created at signup/backfill; visible house placement remains client-side. |
| FR_37 | Upgrade house | Backend supported | housing | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_38 | View partitioned inventory | Partial / integration | inventory / shop / economy | Six partition rules/capacity enforced; current Godot inventory still needs partition-aware rendering. |
| FR_39 | View XP and Aura | Backend supported | inventory / shop / economy | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_40 | Earn and hold Aura | Backend supported | inventory / shop / economy | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_41 | Sell for Aura | Backend supported | inventory / shop / economy | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_42 | Discard an item; Confirm before discarding item | Backend supported | inventory / shop / economy | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_43 | Inventory full warning | Backend supported | inventory / shop / economy | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_44 | View Aura history | Backend supported | inventory / shop / economy | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_45 | Buy from the shop; Insufficient Aura at shop | Backend supported | inventory / shop / economy | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_46 | Daily shop refresh | Backend supported | inventory / shop / economy | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_47 | Preview item before buying | Backend supported | inventory / shop / economy | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_48 | View collection log | Backend supported | inventory / shop / economy | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_49 | View fish log | Backend supported | inventory / shop / economy | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_50 | Adopt starter pet | Partial / integration | pets | Pet row created on profile character selection; unchanged client does not call this endpoint. |
| FR_51 | Pet follows player | Client responsibility | pets | Presentation remains in unchanged Godot client. |
| FR_52 | Feed the pet | Backend supported | pets | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_53 | Name the pet; Rename the pet | Backend supported | pets | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_54 | Pet rests when idle | Partial / integration | pets | Resting state calculated after inactivity; no new pet animation. |
| FR_55 | Equip pet accessory | Partial / integration | pets | Owned accessory validation and persisted equipment; no visual update code. |
| FR_56 | Play fetch with pet | Partial / integration | pets | Timed fetch start/finish and affection; retrieval/pathfinding animation stays client-side. |
| FR_57 | Seasons change over time | Backend supported | world / worker | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_58 | Day and night cycle | Client responsibility | world / worker | Presentation remains in unchanged Godot client. |
| FR_59 | Weather changes; Weather does not block play | Backend supported | world / worker | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_60 | Rain waters crops | Partial / integration | world / worker | Worker waters active stages during rain; historic rain while worker is stopped is not replayed. |
| FR_61 | Seasonal village décor | Client responsibility | world / worker | Presentation remains in unchanged Godot client. |
| FR_62 | Track achievement progress | Backend supported | progression / notifications | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_63 | View achievements; See in-progress achievements | Backend supported | progression / notifications | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_64 | Claim achievement reward | Backend supported | progression / notifications | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_65 | Login streak resets | Backend supported | progression / notifications | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_66 | Level-up alert | Partial / integration | progression / notifications | Durable level-up alert generated; celebratory animation remains client-side. |
| FR_67 | Unlock content by level; See locked content | Backend supported | progression / notifications | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_68 | Track login streak | Backend supported | progression / notifications | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_69 | Give rewards on login | Backend supported | progression / notifications | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_70 | View daily tasks; Complete a daily task | Backend supported | progression / notifications | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_71 | Track task progress | Backend supported | progression / notifications | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_72 | Refresh daily tasks | Backend supported | progression / notifications | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_73 | Rare world event appears; Claim rare event reward | Partial / integration | events / worker | Scheduled limited-time event and once-only item claim; event-specific scene/interaction remains. |
| FR_74 | Friend request alert | Backend supported | notifications / worker | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_75 | Gift alert | Backend supported | notifications / worker | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_76 | View notification list; Empty notification list | Backend supported | notifications / worker | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_77 | Dismiss notification | Backend supported | notifications / worker | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_78 | Live crop-ready alert | Partial / integration | notifications / worker | Worker creates crop-ready alerts; client needs poll/notification display and tile highlight. |
| FR_79 | Unread notification badge | Backend supported | notifications / worker | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_80 | Search and add friends | Backend supported | social / realtime | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_81 | Accept or reject friends | Backend supported | social / realtime | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_82 | Visit friend farm | Partial / integration | social / realtime | Authorized read-only farm data and visit notice; transport/scene switching remains. |
| FR_83 | Remove a friend; Confirm before removing | Backend supported | social / realtime | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_84 | Block self-request | Backend supported | social / realtime | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_85 | Prevent duplicate requests | Backend supported | social / realtime | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_86 | View friend profile | Backend supported | social / realtime | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_87 | Block a player; Unblock a player | Backend supported | social / realtime | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_88 | See online friend count | Partial / integration | social / realtime | Heartbeat-based online status, 60-second timeout; current UI has no subscription. |
| FR_89 | Visit friend's map | Partial / integration | social / realtime | Friend farm metadata/presence room supported; house entry rendering remains. |
| FR_90 | Set status message | Backend supported | social / realtime | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_91 | See friend's last-online time | Backend supported | social / realtime | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_92 | Send an invite; Invite expires | Partial / integration | social / realtime | Five-minute invites/expiry alerts implemented; destinations are personal farms, not arbitrary current coordinates. |
| FR_93 | Real-time movement | Partial / integration | social / realtime | HTTP/WS position snapshots implemented; smooth interpolation and names/leaving effects remain client-side. |
| FR_94 | Send and claim gifts | Backend supported | social / realtime | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_95 | Propose a trade; Cancel a trade proposal | Backend supported | social / realtime | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_96 | Accept a trade; Decline a trade | Backend supported | social / realtime | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_97 | Inventory updates after trade | Backend supported | social / realtime | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_98 | Proximity chat | Partial / integration | social / realtime | Nearby recipient selection and filtered ten-second messages implemented; client speech bubbles/input remain. |
| FR_99 | Send direct message | Backend supported | social / realtime | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_100 | Chat language filter | Backend supported | social / realtime | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_101 | Report a player | Backend supported | social / realtime | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_102 | Use an emote | Partial / integration | social / realtime | Timed nearby emote state; animation rendering remains client-side. |
| FR_103 | Directional walk animation | Client responsibility | realtime / profile / client | Presentation remains in unchanged Godot client. |
| FR_104 | Idle animation | Client responsibility | realtime / profile / client | Presentation remains in unchanged Godot client. |
| FR_105 | Action animations | Client responsibility | realtime / profile / client | Presentation remains in unchanged Godot client. |
| FR_106 | Connection lost message | Client responsibility | realtime / profile / client | Presentation remains in unchanged Godot client. |
| FR_107 | Resume after reconnect; Grace period expires | Partial / integration | realtime / profile / client | Persisted position restored within 60 seconds; existing client reconnect/title-screen behavior is not modified. |
| FR_108 | Auto-save progress | Partial / integration | realtime / profile / client | Every backend action commits; local Godot-only state cannot be autosaved by the server. |
| FR_109 | Manual save | Partial / integration | realtime / profile / client | Authenticated save acknowledgement/timestamp; does not ingest arbitrary local client state. |
| FR_110 | Saves automatically | Partial / integration | realtime / profile / client | Committed server actions persist; exit-triggered local-state submission remains a client integration task. |
| FR_111 | First-time tutorial; Tutorial steps in order | Partial / integration | profile / client | Ordered tutorial state endpoint; no new tutorial overlay. |
| FR_112 | UI tooltips | Client responsibility | profile / client | Presentation remains in unchanged Godot client. |
| FR_113 | Skip tutorial | Partial / integration | profile / client | Persisted skip action; client tutorial closing remains. |
| FR_114 | First-encounter hint | Partial / integration | profile / client | First-encounter acknowledgement persisted; hint display remains. |
| FR_115 | Action sound effects | Client responsibility | profile / client | Presentation remains in unchanged Godot client. |
| FR_116 | Audio settings | Partial / integration | profile / client | Volume preferences persisted; client must read/apply them. |
| FR_117 | Toggle display mode | Partial / integration | profile / client | Display preference persisted; actual window mode remains in Godot. |
| FR_118 | View game version | Client responsibility | profile / client | Presentation remains in unchanged Godot client. |
| FR_119 | View controls help | Client responsibility | profile / client | Presentation remains in unchanged Godot client. |
| FR_120 | Submit feedback | Backend supported | profile / client | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_121 | View credits | Client responsibility | profile / client | Presentation remains in unchanged Godot client. |
| FR_122 | Request password reset; Invalid recovery email | Backend supported | auth / profile | Existing generic recovery response deliberately avoids account enumeration; differs from SRS unknown-email error. |
| FR_123 | Change password; Wrong current password | Backend supported | auth / profile | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_124 | Delete account | Backend supported | auth / profile | Password or verified matching Google identity plus exact username confirmation; cascading deletion policy documented. |
| FR_125 | Confirm account deletion | Backend supported | auth / profile | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |
| FR_126 | View account details | Backend supported | auth / profile | See domain APIs, persisted models, service validation and tests; new client UI is not wired. |

## Deliberate choices and unresolved design details

- FR_18 pre-tilled starter tiles are not created automatically because the supplied server has no authoritative starter plot layout. Existing private worlds and explicit tilling remain.
- The FR_37 “no furniture placement” rule is respected: housing tier upgrades have no indoor furniture feature. FR_28 outdoor decorations are separate, persisted nonblocking records.
- The six SRS partitions are mapping rules, separate from legacy item category strings. All shipped catalog entries receive rules. Legacy/custom catalog entries without a rule must be classified by an operator before relying on partition limits for them.
- No voice chat backend was added: the informal class diagram mentions voice, but the functional requirements describe text proximity/direct messaging.
- Login days are UTC calendar dates; task and shop days follow the global game clock. This is explicit because the SRS does not resolve the two meanings of “day.”
- No user database was reset or migrated. The delivered code and migrations were exercised only against disposable local databases.
