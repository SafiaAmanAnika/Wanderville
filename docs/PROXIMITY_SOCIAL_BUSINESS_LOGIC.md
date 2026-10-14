# Proximity text, voice, gifting, and wishlists

Status: design specification written 14 October 2026. The backend and native Godot client are now implemented; see [delivered setup and protocol](PROXIMITY_BACKEND.md). The first native media transport is PCM over a separate WebSocket with a small-room server mixer; the WebRTC/SFU architecture below remains the future scaling target. The baseline inventory in section 2 describes the original code before these changes. Proposed defaults are tuning decisions, not claims about Roblox or Zepeto behavior.

## 1. Product behavior

When friends meet in an authorized world, show one compact Nearby window with the names in range and actions: Write, Join voice, Gift, Wishlist, Mute, Block, Report. Walking near someone never enables the microphone. Opening Write focuses the composer only after a click or chat shortcut; the proximity prompt itself never steals movement input. Closing the panel preserves the current account's draft.

Nearby is a local audience channel: everyone eligible within the sender's range can receive the message. Selecting a name for Gift or Wishlist does not make Nearby text private. Label the composer “Nearby · visible to players in range.” Use the existing Private tab for direct messages; private messages never become public speech bubbles.

Friends visiting a house still need the existing accepted visit invitation. Friendship alone never admits a player to a farm. Multiple visitors can talk, but each sender/listener pair must independently satisfy proximity and privacy rules.

Social remains usable outside proximity: Friends, Private, Gifts mailbox, and Wishlist are persistent social options. A friend can send an authorized gift while the receiver is offline. Voice and Nearby chat require a live authorized room session.

## 2. What exists today

| Area | Inspected implementation | Extension needed |
| --- | --- | --- |
| Client transport | code/client/autoloads/RealtimeClient.gd uses WebSocketPeer, authentication, move packets every 0.2 seconds, snapshots, reconnect, and message deduplication | Versioned proximity/voice events, request acknowledgements, connection generation |
| Server | code/server/app/modules/realtime/router.py exposes /realtime/ws with enter/move/chat/emote/snapshot | Proximity state, correlated responses, voice authorization |
| Nearby text | realtime/service.py selects recipients within 600 world units, same room, excluding blocks; messages expire after 10 seconds | Explicit audience/room metadata, idempotency and prompt events |
| Message validation | realtime/schemas.py allows 1–500 characters with non-whitespace content; service has roughly one-second cooldown and configurable word filtering | Explicit shared limits and richer abuse controls |
| Visits | Server derives campus or world:{world_id} from ownership/active visit | Reuse this authorization for text and media; invalidate voice on visit end |
| Social UI | Scripts/social_panel.gd offers Nearby/Private and friends | Nearby prompt, voice controls, gift and wishlist views |
| Remote avatars | Scripts/remote_players.gd creates username labels and interpolates avatars | Bubble/speaking overlays for local and remote players |
| Gifts | social/service.py already implements gift creation, inventory debit, mailbox notification, claim, and sender/request-ID deduplication | Client flow, transaction receipt recovery, wishlist link |
| Wishlist and voice | No implementations found in the inspected application source | New models, endpoints, client components and media integration |

Current nearby delivery uses snapshots and saved recipient rows, not a dedicated push fan-out. Keep that distinction when estimating the work. Current socket ownership is process-local and explicitly assumes one Uvicorn worker; scaling needs shared coordination.

## 3. Transport and server responsibilities

Use WSS for authentication, authoritative proximity updates, text, acknowledgements, and voice control. Use WebRTC for actual audio. WebSockets use TCP, whose latency behavior is unsuitable for normal real-time voice; Godot's documentation explicitly makes this distinction: [Using WebSockets](https://docs.godotengine.org/en/stable/tutorials/networking/websocket.html).

Use a server-controlled WebRTC SFU (selective forwarding unit) for group audio. The SFU receives published audio tracks and forwards only the tracks the backend authorizes for each listener. Never give clients permission to subscribe freely to an entire world. Muting volume locally is not a privacy boundary: an unauthorized listener must not receive the track.

Architecture:

    Godot client <-- WSS --> FastAPI realtime gateway
                                  |
                         world/visit + social policy
                                  |
                         proximity and voice control
                                  |
    Godot client <-- WebRTC --> SFU media server
                                  |
                          STUN/TURN connectivity

PostgreSQL retains durable accounts, friendships, blocks, gifts, inventory, wishlists, and necessary audit records. Runtime proximity edges, connection ownership, leases and subscription revisions are ephemeral. Start with one coordinated realtime process; introduce shared runtime storage and pub/sub when deploying multiple workers. The SFU is a separate media service, not a Python audio loop.

WebRTC needs signaling and ICE connectivity. Support TURN for networks where a direct path to media infrastructure fails; use short-lived credentials. [WebRTC connection guide](https://webrtc.org/getting-started/peer-connections).

Important Godot implementation gate: built-in WebRTC networking classes are not proof of a complete microphone/media-track integration. Validate an audio-capable SDK/GDExtension for native exports and a JavaScript media bridge for web exports before promising platform support. Test capture, Opus media, echo cancellation, output routing, mute, and device permission behavior on every target. Godot documents its WebRTC data-channel classes and native extension requirement here: [Godot WebRTC](https://docs.godotengine.org/en/stable/tutorials/networking/webrtc.html). Provider-specific signaling may use its own authenticated WebSocket; application permissions still come from our backend.

## 4. Proximity eligibility and distances

Defaults: retain the existing 600-unit text range; show a prompt upon entering 600 units; dismiss the encounter after exceeding 720 units. The outer threshold prevents UI flicker and does not extend text/voice audibility. Tune these world-unit values against the actual map scale. Evaluate eligibility on accepted movement, room/visit changes and social-policy changes, plus a periodic freshness check.

A pair is eligible only when both sessions are fresh, both are in the same server-resolved room and acoustic zone, neither has blocked the other, and both players' communication permissions allow the action. Campus Nearby text keeps its existing permitted audience; automatic friend prompts and default voice use accepted friendships. Give voice privacy settings Off/Friends/Nearby, default Friends; both sides must permit the pair. Enabling Nearby must be explicit.

Use a spatial grid per room for candidate discovery, then exact squared distance. Never scan all online users for every movement. Do not infer eligibility from client collision areas, display interpolation, claimed room IDs or client-provided recipient lists. Reuse validated server position and movement sequence.

House interiors should become distinct acoustic zones when interiors exist. Initially treat a whole room as one acoustic zone; walls do not magically block sound. Add authored zones/door connectivity later without claiming present-day occlusion.

Encounter state:

    OUTSIDE -> AVAILABLE -> DISMISSED -> OUTSIDE
                   |           |
                   +-> text/voice controls

Enter at distance <=600. Retain encounter UI while distance <=720; show “out of chat range” and disable targeted voice when beyond 600. A closed prompt stays dismissed for that encounter. Re-arm only after the pair has remained outside 720 for two seconds and a 30-second prompt cooldown has passed. Combine several arrivals in one Nearby window. Opening other HUD panels must preserve the existing single-main-panel behavior.

Voice and text use actual <=600 eligibility, independent of the UI state. Blocking, revoked visits, logout, room change and privacy disable invalidate eligibility immediately, without a distance grace period.

## 5. Text send and speech bubble logic

1. Player chooses Write or the chat shortcut; disable movement shortcuts while the composer owns focus. Escape returns focus to the world.
2. Client submits chat with body and stable request_id. Sender identity comes from the authenticated socket. Trim outer whitespace, reject empty text and enforce the server's 500-character limit plus a bounded packet byte size.
3. Server validates session, current room, chat permission, cooldown and content policy. The existing word filter is a baseline, not comprehensive moderation.
4. Under a consistent authorization/position snapshot, compute exact eligible recipients at acceptance time, plus sender echo. New arrivals never receive earlier messages simply by walking into range.
5. Save message and recipient records atomically, with room, sender session generation, server timestamps and expiry. Persist sender/request_id uniqueness; retrying the same payload returns the same receipt, and reuse with different text returns IDEMPOTENCY_CONFLICT. Retain deduplication receipts beyond the short message TTL, for a documented retry window such as 24 hours.
6. Return chat.accepted with message_id and request_id. Deliver chat.message through authorized push or the existing snapshots. Client deduplicates both paths using message_id. A socket send succeeding is not proof the server accepted the message.
7. Before delivery, recheck room and blocks. A receiver who moved out of range after acceptance may receive the accepted message until expiry, provided they remain in the same room and eligible under privacy rules. Do not widen the original recipient set. On room change purge pending delivery and UI buffers tied to the previous room.
8. Render accepted, filtered text in Nearby history and a bubble above the sender. Never broadcast the optimistic local draft. Failed sends retain the draft with Retry.

Bubble presentation: plain text with markup disabled, wrapped width, at most three visible lines, five-second display bounded by the server message expiry, and full text available in the panel. Maintain at most three queued bubbles per avatar and drop expired entries. The sender also sees their accepted bubble. Do not show a floating bubble when its avatar is absent; history can still show the authorized message. Remove bubbles on block, avatar removal, room change and logout. The current remote actor disables processing, so bubble timers/animations need an enabled overlay controller or explicitly independent processing.

Typing indicators are optional, ephemeral and rate limited: no more than one update per second, expire after three seconds, sent only to currently eligible recipients. Never send draft text.

## 6. Voice lifecycle and routing

Voice state per player: OFF -> JOINING -> LISTENING/MUTED -> TALKING -> LEAVING -> OFF. Permission/device failures return to a visible error with text still available. Join voice is explicit; ask for microphone permission only after that action. Start muted, with push-to-talk as the initial default. Listen-only is allowed when the player chooses it. Leaving voice stops capture and releases the media session.

For each directional audio track A -> B, require:

    valid_session(A) and valid_session(B)
    and same_authorized_room_and_zone(A, B)
    and distance(A, B) <= 600
    and privacy_allows_both(A, B)
    and not blocked_either_direction(A, B)
    and A.voice_joined and B.voice_joined
    and A.publish_allowed and B.listen_allowed
    and not B.has_muted(A)

A self-mute stops publishing; deafen stops listening and also mutes the microphone. Block revokes both directions and closes associated social access. Per-player mute affects the listener's subscriptions without telling the muted player who muted them. Host controls may mute/kick visitors according to host policy, but cannot turn on another person's microphone. Removing a friendship reevaluates Friends-only voice immediately.

No transitive groups: if A is near B and B near C, A cannot hear C unless A/C independently qualify. Keep one media connection per player/room when feasible; update subscriptions as people move rather than creating a call for every pair.

Distance gain proposal: full volume through 150 units; smoothly reduce to zero at 600. Example gain = clamp((600 - distance) / 450, 0, 1). Only apply gain to already authorized tracks. Use direction-based panning if desired. Use a speaking indicator driven by media activity, not client-declared permission. Walking past 600 removes the media subscription; returning can restore it while the player remains explicitly joined to voice in that room.

Join flow: validate session and policy -> grant short-lived room/player/connection-bound media credentials -> connect to SFU -> confirm media connection -> create authorized subscriptions. Start with subscribe-all disabled and publishing gated. Backend controls subscription additions/removals and track identity; never accept a forged sender ID.

On movement/permission changes, increment policy revision and apply subscription changes in order. Reject stale additions after a newer revoke. Immediate revoke is the normal path; short renewable media authorization leases are the failure backstop. Require a maximum two-second lease/reconciliation window as an initial target; the media integration must enforce expiry if the gateway disappears. If the chosen SFU cannot enforce this, add a watchdog/controller or do not ship that integration. JWT expiry alone may not disconnect an established session.

Logout, visit end, room change, socket replacement and control-channel loss close the associated media session. Stop local capture immediately when losing control connectivity; revoke server-side forwarding too. A network outage cannot guarantee zero in-flight audio, so measure the revocation bound. Reconnect with a new generation, recompute permissions, and require an explicit voice rejoin. Text reconnection never silently resumes the microphone.

No raw audio storage by default. Reports reference participants, room/session and timestamps. Any future recording/transcription requires a separate product decision and explicit user-facing consent flow.

## 7. WebSocket contract

Preserve existing auth/enter/move/chat/emote/snapshot packets during migration. Negotiate a protocol version/capabilities after auth before sending new events. Existing clients only understand snapshot/error; deploy server compatibility first.

New command envelope example:

    {"type":"chat","request_id":"uuid","data":{"body":"Hello!"}}

New event example:

    {"type":"proximity.updated","event_id":"uuid","sequence":42,
     "room":"world:7","room_epoch":3,
     "data":{"nearby":[{"player_id":12,"can_text":true,"can_voice":true}]}}

| Direction | Type | Purpose |
| --- | --- | --- |
| Server -> client | proximity.updated | Current permitted nearby peers and action flags |
| Client -> server | chat | Existing Nearby send, extended with idempotency |
| Server -> client | chat.accepted / chat.message | Receipt and filtered authorized message |
| Both | chat.typing | Optional scoped transient indicator |
| Client -> server | voice.join / voice.leave | Explicit media participation |
| Client -> server | voice.state | Mute/deafen intent; server validates resulting policy |
| Server -> client | voice.ready | Short-lived media connection details, no server secrets |
| Server -> client | voice.updated / voice.revoked | Authorized state/reason/revision |
| Server -> client | social.updated | Invalidate authorized gift/wishlist/friend views after commit |
| Server -> client | error | request_id, stable error code, retryability, safe message |

Initial snapshots include current nearby eligibility and voice state for recovery. Separate transport event sequence from existing movement sequence. Include room_epoch and connection generation so delayed events cannot attach to a new room or login. Heartbeats, bounded outbound queues and disconnect-on-backpressure prevent stalled clients accumulating unlimited data. Apply strict schemas, packet sizes and per-account/per-connection rate limits. Keep first-frame auth timeout and reauthentication; validate web origins against configured allowed origins.

Useful error codes: OUT_OF_RANGE, VISIT_ENDED, VOICE_DISABLED, VOICE_PERMISSION_DENIED, MEDIA_UNAVAILABLE, CHAT_COOLDOWN, IDEMPOTENCY_CONFLICT, INVENTORY_FULL, WISHLIST_NOT_VISIBLE. Do not reveal private block relationships in error text.

## 8. Gift and wishlist business rules

Gift flow: choose a friend -> Gift -> select an owned giftable item and quantity -> display recipient/item/quantity -> confirm -> call existing POST /social/gifts with stable request_id. Debit inventory and create the mailbox gift in one transaction. Notify only after commit. A timeout means unknown outcome: retry/query the original receipt, never invent another request_id automatically. Keep a pending command across restarts, as the store already does.

Claim through existing POST /social/gifts/{gift_id}/claim. Verify receiver ownership, block policy, capacity and not-already-claimed under deterministic player locks. A full inventory leaves the gift unclaimed without losing items. A duplicate claim cannot create another stack; treat the existing ALREADY_CLAIMED response as a prompt to refresh the receipt. Existing block rules prevent claiming a gift from a blocked player; preserve it pending rather than silently deleting or refunding it. Gifts are not automatically cancelled by proximity loss. No real-money or buy-and-send operation is introduced here.

Add Wishlist to Social and friend profiles. Default visibility Friends; support Private. Owner can add/remove catalog items, requested quantity and priority. Reject nonexistent/non-giftable items, invalid quantities and duplicate active item rows; set a reasonable per-player cap such as 50. Only the owner edits. Reading another wishlist requires current friendship, visibility permission and no block. A wishlist never grants spending authority.

Selecting “Gift from wishlist” prefills the gift form but still requires confirmation. If the sender lacks the item, show View in Store; purchase remains the existing separate confirmed transaction.

Track requested quantity, pending allocated gifts and fulfilled quantity for linked gifts. At gift acceptance, lock/recheck the wishlist entry and reserve available desired quantity in the same transaction as inventory debit. Reject stale over-allocation with WISHLIST_CHANGED and return fresh quantities. This prevents two friends simultaneously overfilling one remaining request. On claim, move allocation from pending to fulfilled. Removing an entry hides it but cannot destroy a pending gift. Lowering requested quantity below pending+fulfilled is rejected. Explicit unlinked gifts can still be sent and do not fulfill a wishlist automatically. Persist an entry version for optimistic UI updates. Return aggregates to viewers; do not expose other senders' identities.

Proposed HTTPS endpoints (mounted under the project's normal API base):

| Endpoint | Rule |
| --- | --- |
| GET /social/wishlist | Own entries and progress |
| PUT /social/wishlist/{item_code} | Owner create/update with expected version |
| DELETE /social/wishlist/{item_code} | Owner soft removal |
| GET /social/players/{player_id}/wishlist | Authorized viewer only |
| PATCH /social/preferences | Wishlist visibility, voice privacy, prompt preference |
| GET /social/gifts/requests/{request_id} | Sender-scoped retry receipt; add if absent |

Extend existing gift requests with optional wishlist_entry_id and expected version. Include that linkage in the immutable idempotency comparison. Keep durable gift/wishlist commands on HTTPS; use WSS to notify other views after commit. If commands are later exposed over WSS, call exactly the same transactional service.

## 9. Data, concurrency and deployment

New durable records: social communication preferences; wishlist entries with owner/item uniqueness, visibility policy, quantity/version and soft-delete state; gift-to-wishlist allocations; text retry receipts with payload hash; moderation metadata if enabled. Extend nearby messages with room, sender generation and timestamps. Retain existing recipient tables. Use migrations rather than client-managed schema changes.

Runtime records: player connection generation/owner, validated presence freshness, proximity pair state, dismissed encounter state, voice membership, directed subscription revision and expiry. PostgreSQL remains the initial presence source; avoid adding extra durable writes per voice frame. Media packets never pass through the database.

Serialize policy changes per room or use revisions to avoid stale movement reopening revoked access. Lock player IDs in stable order for economic operations, then wishlist/allocation rows in a documented consistent order. Use unique constraints as the final duplicate guard. Use a transactional outbox for durable gift/wishlist notifications; clients also refresh authoritative state on reconnect. Ephemeral voice/proximity can recover from snapshots instead of durable event replay.

Before multiple gateway workers, replace process-local socket ownership with shared leases and distributed generation checks; add room event routing and shared rate limits. Preserve the existing protection that an old socket's cleanup cannot expire its replacement. Pub/sub delivery loss must be recoverable via snapshot/revision reconciliation. Keep blocking database work off the async event loop and release DB sessions between frames.

Deploy API/WSS behind TLS, SFU on its documented media ports, and TURN with authenticated short-lived credentials. Keep SFU administration and signing credentials server-side. Size media egress from simultaneous publishers/listeners and authorized directed edges; cap room/voice concurrency server-side and expose VOICE_ROOM_FULL rather than overloading. Validate deployment media-port support before choosing hosting. Text remains available during an SFU outage.

## 10. Implementation sequence and acceptance checks

1. Extend existing realtime schemas/service with configurable distances, pair policy, room epochs, stable text receipts and capability negotiation. Keep existing nearby behavior compatible.
2. Add ProximityController.gd, the compact Nearby prompt, and speech-bubble overlay; connect them to RealtimeClient and existing social_panel.gd/remote_players.gd. Preserve map, house scenes and tilesets.
3. Prove audio capture/playback/SFU integration on intended exports, then add VoiceClient.gd behind a feature flag. Ship join/mute/leave and server subscription enforcement together.
4. Add preferences/wishlist migrations and service rules; expose the existing gift mailbox and gift workflow in Social, with pending-receipt recovery.
5. Add distributed runtime coordination only when needed for the chosen deployment topology; load-test the intended room and concurrency limits before launch.

Required acceptance scenarios:

- Two accepted friends in the same authorized farm enter 600 units: one prompt appears, Write works, microphone stays off.
- Multiple players crossing the threshold do not steal focus or create stacked modals; boundary movement does not spam prompts.
- A sends a message: only original eligible recipients and A receive one accepted copy and bubble; a late arrival gets no history.
- Same coordinates in different worlds/interiors do not share text/voice; forged rooms/positions/recipient IDs are rejected.
- A near B, B near C, A far from C: no A/C audio forwarding.
- Both voice-joined players hear authorized speech; mic denied/SFU unavailable still allows text.
- Leaving 600, blocking, friendship removal under Friends mode, ending a visit, replacing a socket, and control failure revoke media within the measured bound. A stale grant cannot restore it.
- Private messages never appear as Nearby bubbles; stale room events and expired bubbles are discarded.
- Duplicate/retried text creates one message; unknown send outcomes preserve the request ID and draft state.
- Duplicate gifts, concurrent claims, full inventories and crashes cannot duplicate or lose items. Receiver going offline does not lose a gift.
- Two gifts against the final wishlist quantity cannot over-allocate. Private or blocked wishlists cannot be read by changing IDs.
- Reconnect resets ephemeral permissions from server state, reconciles durable receipts and never resumes a microphone automatically.

Measure prompt latency, text acceptance/delivery latency, voice join time, audio loss/jitter, subscription revoke latency, socket queue depth, rejected authorization attempts and gift retry outcomes. Proposed initial targets: prompt within 500 ms of server-accepted movement, text delivered within one second under healthy network conditions, and fail-closed voice revocation within two seconds on control failure. These are release criteria to verify, not current guarantees.
