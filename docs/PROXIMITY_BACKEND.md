# Proximity social: native Godot + Python

The shipped client is GDScript. There is no JavaScript companion or browser handoff.
The reusable native UI attaches to the existing world HUD; a lightweight Godot
scene exercises the same functionality without loading the farm map.

## Run

From code/server, use Python 3.12 and the existing server environment:

    .venv312/Scripts/python.exe -m pip install -r requirements.txt
    .venv312/Scripts/python.exe -m alembic upgrade head
    .venv312/Scripts/python.exe -m app.db.seed
    .venv312/Scripts/python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --workers 1 --ws-max-size 65536 --ws-max-queue 8

Back up an existing database before migrating. Migration 0008_proximity_social
adds preferences, wishlists, gift allocations, social revisions, chat receipts
and room epochs. The upgrade is additive. Test runners use disposable databases;
they never migrate the database configured in your local .env.

The local ignored .env has voice enabled, a 600-unit interaction radius,
720-unit encounter exit radius, eight voice participants per room and 32 per
process. Existing credentials are preserved. Documented defaults are in
.env.example; real secrets must not enter Git. Native voice needs neither TURN
nor aiortc.

Open Scenes/social_standalone.tscn and run the current scene (F6), or from the
repository root:

    $env:WANDERVILLE_API_URL = 'http://127.0.0.1:8000'
    godot --path code/client res://Scenes/social_standalone.tscn

Use two verified accounts in separate instances. Arrow keys move the standalone
player. The existing Social panel handles friend requests, private messages and
farm invitations. Accepted friends inside the perimeter produce a nonmodal
prompt. Write sends nearby text. Join voice starts listening with the microphone
off. Hold Talk to transmit; release, focus loss, disconnect, room change or Leave
voice stops capture. Deafen also mutes transmission. Gifts / Wishlist opens the
selected friend's list; My wishlist / Privacy opens personal settings. Gift
confirmation consumes owned inventory only after server acceptance. Recipients
claim gifts in the inbox.

## Client modules

- autoloads/RealtimeClient.gd: protocol v2, sequence validation, correlated
  commands, half-second heartbeats, refresh/reconnect and room epochs.
- Scripts/social/proximity_social.gd: nearby friend prompt, text composer,
  speech bubbles, block/report and voice/social controls.
- Scripts/social/proximity_voice.gd: push-to-talk capture, resampling, bounded
  audio queues, native WebSocket and mixed playback.
- Scripts/social/community_window.gd: catalog picker, wishlist quantities and
  priorities, privacy, confirmation, durable gift recovery and inbox claims.
- Scripts/social/standalone_social.gd: lightweight native login/world harness.

Microphone capture uses Godot's [AudioStreamMicrophone](https://docs.godotengine.org/en/stable/classes/class_audiostreammicrophone.html)
and [AudioEffectCapture](https://docs.godotengine.org/en/stable/classes/class_audioeffectcapture.html).
Audio input is enabled in project.godot. Platform exports must include microphone
permissions (Android RECORD_AUDIO, macOS microphone usage description). The game
never silently enables capture when somebody approaches.

## Gameplay/control WebSocket

Connect to /realtime/ws, then send:

    {"type":"auth","protocol_version":2,"token":"<access token>"}

Snapshots contain connection_id, monotonic sequence, data, optional request_id
and events. Data contains players, messages, room/room_epoch, proximity, voice
and social_revision. Protocol v1 remains supported. One gameplay connection per
player is allowed; a replacement revokes the old connection and its media.

| Type | Data | Result |
| --- | --- | --- |
| enter | owner_id omitted for campus, otherwise host player ID | Authorized room snapshot |
| move | x, y, sequence | Server-validated position |
| heartbeat | Empty object every 0.5 seconds | Presence/control lease renewal |
| chat | body; request_id in outer envelope | chat.accepted with message_id |
| proximity.dismiss | target_id | Encounter prompt dismissed |
| voice.join | transport: pcm-websocket | voice.ready with session_id; starts muted |
| voice.state | session_id, muted, deafened, muted_players | Updated voice snapshot |
| voice.leave | Empty object | voice.left |

Use 8–64 character alphanumeric/underscore/hyphen request IDs. Reuse the same ID
and body after uncertain text delivery. The server keeps receipts for 24 hours;
speech bubbles expire after ten seconds. Late joiners and players returning to
a room do not receive its historical nearby text. Errors remain correlated to
requests: voice denial does not eject someone from an authorized room.

Proximity uses exact Euclidean distance, authoritative room and validated
positions. Text reaches eligible players within 600 units at send time, including
strangers. Friend prompts retain their encounter until the outer exit boundary;
dismissal observes encounter cooldown. Voice defaults to friends on both sides.
Privacy can be off, friends or nearby; blocks override everything. Farm presence
requires ownership or an active accepted visit. An invitation alone grants no
admission. Guest removal/end invalidates media authorization immediately.

## Native audio WebSocket

After voice.ready, connect to /realtime/voice/ws and send:

    {"type":"auth","token":"<access token>","connection_id":"<game connection>","session_id":"<voice session>","capabilities":["silence_suppression"]}

The server replies voice.connected. Each binary message is exactly 960 signed
PCM16 little-endian mono samples at 48 kHz: 1920 bytes / 20 ms. Clients send only
while explicitly transmitting. Each listener receives one server mix. Audio
cannot move the player, grant proximity or renew the game's control lease. This
socket does not replace the gameplay socket.

A client that declares the `silence_suppression` capability is sent nothing at
all while the room is quiet: the mixer produces a frame every 20 ms for every
listener, and without this the server spends 96 kB/s per listener on silence
alone, whether or not anybody is speaking. A silent room instead produces one
`{"type":"voice.idle"}` keepalive every `VOICE_IDLE_KEEPALIVE_SECONDS` (five
seconds by default), which is the client's only evidence that the socket is
still alive. A client that does not declare the capability keeps receiving the
frames of silence it always received, so an installed client and a new server
work together during a rollout. The WebRTC path is unchanged: a media track
has to produce frames at a steady rate, so its silence is not suppressed.

Every mix checks current room, mutual permissions, blocks, listener mute,
deafen, distance and fresh control/policy leases. Policies invalidate only after
the relevant database transaction commits. Directed pairwise permissions prevent
transitive listening through another player. Gain falls with distance; a player
cannot hear their own stream. Queued contributions are rechecked at playback.
Malformed packets, excessive frame rates, slow receivers and stale sessions are
bounded or disconnected.

This first native transport uses uncompressed PCM: about 768 kbit/s in each
direction while transmitting/receiving, before network overhead. A quiet room
costs a capable client almost nothing, but a room with one speaker still costs
every listener the full 768 kbit/s, because the server mixes and sends one PCM
stream per listener. There is no native echo cancellation; headphones and
push-to-talk are recommended. TCP can stall under packet loss. Hosted
deployments require HTTPS/WSS. A future native Opus/WebRTC integration can
retain the control protocol, authorization and UI. This is a small-room MCU, not
a production-scale SFU.

Optional WebRTC clients can install requirements-voice.txt, join with transport
webrtc-mixed-audio, then send voice.offer with session_id and full ICE-gathered
SDP. One audio transceiver is accepted; the response is voice.answer. Configured
TURN uses expiring HMAC credentials. Never invent TURN URLs or ship TURN shared
secrets in the client.

Use one API worker and one server instance: session/media leases are process-local.
Multiple workers require shared coordination and a media architecture first.
The server mixes audio; voice is not end-to-end encrypted through it. Audio is
not recorded.

## Social HTTP API

All routes require the logged-in player's bearer token.

| Route | Purpose |
| --- | --- |
| GET/PATCH /social/preferences | voice_privacy, wishlist_visibility, proximity_prompts |
| GET /social/wishlist | Active personal wishlist |
| GET /social/players/{id}/wishlist | Accepted friend's visible list |
| GET /social/wishlist/{item_code} | Personal entry, including removed versions |
| PUT /social/wishlist/{item_code} | quantity 1–99, priority 0–10, expected_version |
| DELETE /social/wishlist/{item_code}?expected_version=N | Versioned soft removal |
| POST /social/gifts | target_id, item_code, quantity, request_id; optional wishlist link |
| GET /social/gifts/requests/{request_id} | Sender's committed receipt |
| GET /social/gifts | Unclaimed received gifts |
| POST /social/gifts/{id}/claim | Claim into inventory, enforcing capacity |

Linked gifts include wishlist_entry_id and wishlist_version. The server locks
affected player rows, validates friendship/inventory/privacy/version, reserves
the wish quantity, debits inventory and creates one gift atomically. Pending
and fulfilled counts prevent oversupply. Conflicting/stale versions require
refresh. Wishlist removal preserves already-sent gifts. Only the intended
recipient can claim; repeated claims never duplicate inventory.

The client persists a pending gift under an API/account-specific local filename
before sending. It stores the payload and request ID, never tokens. Recover
pending gift checks the receipt, retrying the same request only if none exists.
Uncertain failures retain it; another gift is blocked until resolution. Godot
JSON numbers are converted back to integers for strict backend validation.
Privacy and gift changes increment durable social revisions.

## Verification

See [recorded results and remaining manual checks](PROXIMITY_VERIFICATION.md).

From code/server:

    .venv312/Scripts/python.exe -m pytest -q --disable-warnings
    .venv312/Scripts/python.exe scripts/verify_integration.py --postgres
    .venv312/Scripts/python.exe scripts/verify_integration.py --godot <godot.exe> --social
    .venv312/Scripts/python.exe scripts/verify_integration.py --godot <godot.exe> --social --render
    .venv312/Scripts/python.exe scripts/verify_integration.py --godot <godot.exe> --hud

Add PostgreSQL's bin directory to PATH for --postgres. It creates an isolated
cluster; it does not reset the configured development/cloud database.

The native two-account test exercises real Godot controls, WebSocket chat,
friend prompts, speech bubbles, initially-muted voice, synthetic PCM delivery,
wishlist editing, confirmation, loss of a committed gift response, receipt
recovery, claiming and disconnect cleanup. Synthetic audio verifies transport;
physical microphones, permission dialogs and subjective quality still need a
two-device manual check. SQLite and isolated PostgreSQL tests cover migrations,
concurrency, privacy, visits, blocks, receipts and native/WebRTC media enforcement.
Artifacts stay in ignored code/server/.verification directories.

## Native Opus (compression)

The voice path can use Opus to cut bandwidth by roughly 96% with no unacceptable change in the audio the ear hears. The protocol is negotiated per client rather than forced on everyone, so a client without the decoder keeps using raw PCM and loses nothing except the saving.

### Capabilities
- silence_suppression: sent in {"type":"auth", ... "capabilities":[...]}. Without it the server assumes the client expects every frame (legacy behaviour) and does not drop silent frames.
- opus: sent in the same list to ask for compressed audio. The server answers with {"type":"voice.format","encoding":"opus"} if it is enabled; otherwise it falls back to pcm_s16le.

### Framing
- PCM frames are the raw i16 little-endian mono samples as before.
- Opus frames are prefixed with a single marker byte  x01 followed by the Opus payload: ytes([1]) + opus_frame. The client strips the marker before handing the bytes to the decoder.
- oice.format is sent before oice.connected so the client knows which decoder to use for the session.

### Behaviour
- The server encodes with libopus (CBR, 24 kbit/s, VOIP) in pp/modules/realtime/opus.py. If PyAV/libopus is unavailable or encoding fails, it falls back to PCM for that session.
- The client uses a native GDExtension (code/client/native/opus/) that wraps libopus. If the extension is not present or cannot be instantiated, the client falls back to PCM.
- Silence suppression still applies: an idle room produces 0 audio bytes on either path, and the server still sends oice.idle keepalives every oice_idle_keepalive_seconds.
- Jitter is bounded on the client (target ~3 frames, max ~10). Damaged Opus frames are dropped rather than played as noise; the decoder reports the reason via get_last_error().

### Build
The extension must be compiled against godot-cpp (pinned) and libopus (pinned). See code/client/native/opus/README.md or uild.ps1/uild.sh. In CI the Opus extension workflow builds it on Windows x64 and macOS arm64/x64 and runs code/client/tests/opus_extension_check.gd after --import.
