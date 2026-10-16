# Multiplayer Admission — Architecture and Local Setup

This document covers the Godot dedicated multiplayer server and the admission
ticket flow that lets it identify players. It does **not** cover movement
synchronisation, which is a separate phase.

## Status

**Implemented and verified.** Two separate Godot processes authenticate against
one headless Godot server, with identities decided by the existing FastAPI
backend. Movement is *not* migrated: the Python WebSocket transport remains the
default and the only transport carrying gameplay traffic.

| Setting | Default | Meaning |
| --- | --- | --- |
| `MULTIPLAYER_TRANSPORT` | `legacy` | Existing Python WebSocket movement. Unchanged. |
| `PRESENCE_BACKEND` | `database` | Existing Postgres presence. Unchanged. |

## Data flow

```
 Godot client                      Godot dedicated server            FastAPI
 --------------                    ---------------------            -------
 existing login  ---HTTPS---------> (no)
 access token
       |
       +-- POST /multiplayer/tickets ---------------------------------->  verifies
       |     <---------------- ticket (30s, single use)                  account
       |
       +-- ENet connect ------------------------------------------------->
       +-- send_auth(ticket) ------->  _on_auth()
                                          |
                                          +-- POST /internal/multiplayer/
                                          |   tickets/consume  ----------->  spends the
                                          |     <---------------- player_id   ticket
                                          |
                                          +-- send_auth(identity) ------->  client
                                          |                                     admitted
                                          +-- complete_auth(peer)             complete_auth(1)
```

The identity in that diagram comes from the backend. No client-supplied player
id is read anywhere on the server, and no account credential or refresh token
ever reaches the ENet transport.

## Why admission exists

A dedicated server must learn "which player is this peer" without holding a
credential. Forwarding a bearer token onto ENet would put a reusable,
long-lived secret on an unencrypted transport and would let anyone who sniffed
it impersonate the player over HTTPS too. A ticket is the opposite: worthless
outside one handshake, single use, and short lived.

## Godot's built-in authentication

Admission uses `SceneMultiplayer`'s own workflow rather than a custom protocol.
While `auth_callback` is set, a connecting peer stays in the *authenticating*
state: it is excluded from `get_peers()`, `peer_connected` is not emitted for
it, and only authentication data is exchanged.

The callback returns `false`, which deliberately leaves the peer authenticating
while the ticket is validated. `complete_auth()` is called only on a
backend-verified identity.

**Both peers must set `auth_callback`, and both must complete.** Verified
empirically — a client that omits it gets `ERR_INVALID_PARAMETER` from
`send_auth()`, because Godot only tracks a peer as authenticatable when the
*local* side is also authenticating. Two real Godot processes were used to
confirm this rather than reasoning about it.

### Ticket lifetime versus auth timeout

The admission ticket lives 30 seconds; `auth_timeout` is 10. The window must be
long enough for the backend HTTP round trip and shorter than the ticket, so a
peer that cannot be validated in time is dropped rather than admitted on a
stale answer.

## Transport security — what this is not

Plain ENet is **not encrypted**. The ticket and the internal host secret both
travel in the clear.

* A single-use ticket limits *credential* exposure: it cannot be replayed, and
  it expires in 30 seconds. It provides no confidentiality.
* The internal endpoint uses a shared bearer secret compared in constant time,
  read only from the backend environment and never from a client export. An
  unset secret rejects everyone rather than trusting an empty header.
* `MULTIPLAYER_HOST_ALLOWLIST` is development-only; it is rejected outside
  development.

This is a **local and trusted-network design**. It is not production-grade for
the public internet. A public deployment needs TLS or a private tunnel, and
that exposure has not been reviewed.

## Local setup

Four processes. FastAPI must be running first.

### 1. Database and backend

```
Start-Local-Server.cmd
```

### 2. Dedicated Godot server

The backend's `MULTIPLAYER_BRIDGE_SECRET` must match the server's.

```
$env:MULTIPLAYER_BRIDGE_SECRET = "some-shared-secret"
$env:GODOT_MULTIPLAYER_PORT    = "24567"
$env:MULTIPLAYER_BRIDGE_URL    = "http://127.0.0.1:8000"
Start-Local-Multiplayer-Server.cmd
```

It prints, and writes to `GODOT_MULTIPLAYER_READY_FILE` when set:

```
[DedicatedServer] listening on udp/24567 bind=0.0.0.0 server_id=... auth_timeout=10.0s
```

`MULTIPLAYER_BRIDGE_SECRET` is deliberately not defaulted — the launcher
refuses to start without it rather than listening while unable to authenticate
anybody.

### 3. Two clients

Start the game normally (`Start-Local-Game.cmd`) for each player. To exercise
admission headlessly instead:

```
$env:MULTIPLAYER_BRIDGE_SECRET = "some-shared-secret"
$env:TEST_API_URL   = "http://127.0.0.1:8000"
$env:TEST_TOKEN     = "<player access token>"
$env:TEST_USERNAME  = "peer_one"
$env:TEST_PLAYER_ID = "1"
$env:TEST_HOST      = "127.0.0.1"
$env:TEST_PORT      = "24567"
code\client\Godot_v4.6.2-stable_win64.exe --headless --path code\client res://Scenes/network/TestHarness.tscn
```

Each prints one machine-readable line:

```
RESULT {"event":"admitted","ok":true,"player_id":1586,...}
```

Note a client's `localhost` is its own machine. A remote player needs
`GODOT_MULTIPLAYER_HOST` pointed at the host's LAN address and UDP `24567`
open on the firewall.

## Tests

```
# Real two-peer ENet integration, six tests, ~100s
$env:GODOT_EXE = "path\to\Godot_v4.6.2-stable_win64.exe"
pytest tests/integration/test_multiplayer_enet.py -q

# Ticket security without Godot
pytest tests/integration/test_multiplayer_admission.py -q
```

The ENet suite is **skipped, not failed**, when the Godot executable cannot be
found, so an environment that cannot run it never reports a pass.

It starts an isolated FastAPI on its own port against
`WANDERVILLE_TEST_DATABASE_URL`, seeds it, creates disposable accounts, and
gives every test a private temporary directory and a free UDP port.

## Windows notes worth knowing

These cost real time to find and are all verified:

* **Piping the Godot server's stdout prevents it from starting.** It prints the
  engine banner and never reaches `_ready`. Redirect to a file instead.
* **Do not use `free_port_is_free`-style TCP probes for UDP.** Bind the socket
  to confirm, as the harness does.
* **Terminated Godot processes hold the UDP port briefly.** The harness waits
  for a genuinely free port and gives each test its own.
* **Kill only processes this harness started.** Nothing here terminates
  unrelated applications that happen to hold a matching port.

## Not implemented

Deliberately out of scope for this phase:

* Movement, interpolation, prediction or reconciliation
* Remote avatar spawning and presentation
* Farm-room and private-world transitions on ENet
* The trusted bridge into `position_projection.py`
* Any ENet traffic in the live gameplay scenes

## Next phase

The interfaces the movement phase needs already exist:

* `DedicatedServer.refuse_unless_admitted(peer_id)` — guard for any gameplay RPC
* `PeerRegistry.admit()` — the single peer-id-to-player-id mapping
* `BackendBridge` — the private, authenticated channel to the backend
* `room_members(room)` — canonical rooms (`campus`, `world:{world_id}`)

Movement can feed validated positions through `BackendBridge` into the existing
`position_projection.py`, which already has the memory-authority semantics and
would not need redesign.