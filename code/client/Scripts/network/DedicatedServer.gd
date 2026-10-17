extends Node
class_name DedicatedServer
## Headless Godot 4.6 multiplayer server with built-in peer authentication.
##
## Uses SceneMultiplayer's own authentication workflow rather than a custom
## protocol, because it already enforces the property this server needs: while
## ``auth_callback`` is set, a connecting peer stays in the *authenticating*
## state. It is excluded from ``get_peers()``, ``peer_connected`` is not emitted
## for it, and only authentication data is exchanged. Nothing else about the
## connection is usable until authentication completes.
##
## The sequence is:
##1. A peer connects and SceneMultiplayer emits ``peer_authenticating``.
##2. The client sends its admission ticket with ``send_auth``.
##3. ``_on_auth`` runs, returns false -- which deliberately leaves the peer
##    authenticating -- and starts validating the ticket with the backend.
##4. On success ``complete_auth(peer_id)`` is called, and only then does
##    ``peer_connected`` fire and the peer appear in ``get_peers()``.
##5. On failure the peer is disconnected instead.
##
## The identity always comes from the backend's answer. No client-supplied
## player id is read anywhere in this file.
##
## Transport warning: plain ENet is not encrypted. A ticket stops an account
## credential from being replayable, but the ticket and the host secret travel
## in the clear. This is a development design; a public deployment needs TLS or
## a trusted private network.

signal peer_admitted(peer_id: int, player_id: int, username: String)
signal peer_rejected(peer_id: int, reason: String)
signal peer_left(peer_id: int, player_id: int)
signal server_ready(port: int)

const LOG_PREFIX := "[DedicatedServer] "

var registry := PeerRegistry.new()
var bridge: BackendBridge
## The shared RPC endpoint. Created in code as a direct child of this scene root
## so that, with root_path pointing here, its relative RPC path is identical to
## the client's. See NetworkLink for why that matters.
var link: NetworkLink
## The campus movement simulation. Owns every authoritative position.
var movement: MovementAuthority

var _port := NetworkConfig.DEFAULT_PORT
var _bound_address := "0.0.0.0"
var _running := false
var _server_id := ""
## Peers currently being validated, so a slow backend call is not started twice.
var _pending: Dictionary = {}
## Identities of peers whose handshake completed but whose connection callback has
## not fired yet. They are not yet reachable by RPC, so they are not yet announced.
var _awaiting_connect: Dictionary = {}


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		push_warning(
			LOG_PREFIX + "expected a headless display, got " + DisplayServer.get_name()
		)
	_start()


func _start() -> void:
	_port = NetworkConfig.port()
	# Before the peer is created: every side must agree on root_path before any
	# packet exists, and the children this is about to add must be in the tree.
	link = NetworkLink.new()
	link.name = "NetworkLink"
	add_child(link)

	# The movement simulation is opt-in. Building the real campus collision costs
	# roughly 15 seconds, and an admission-only run must not pay for a movement
	# world it never touches -- worse, paying it mid-test would stall the server's
	# main thread during the first admission and starve the clients' handshake.
	if OS.get_environment("GODOT_MOVEMENT_ENABLED") == "1":
		movement = MovementAuthority.new()
		movement.name = "MovementAuthority"
		add_child(movement)
		movement.setup(self, link)
	else:
		print(LOG_PREFIX + "movement simulation disabled (GODOT_MOVEMENT_ENABLED!=1)")

	_bound_address = OS.get_environment("GODOT_MULTIPLAYER_BIND")
	if _bound_address == "":
		_bound_address = "0.0.0.0"
	_server_id = OS.get_environment("GODOT_MULTIPLAYER_SERVER_ID")
	if _server_id == "":
		_server_id = "godot-%d" % OS.get_process_id()

	bridge = BackendBridge.new("", "", self)
	var scene_multiplayer := multiplayer as SceneMultiplayer
	# Bounded, and comfortably inside the 30 second ticket lifetime: if the
	# backend cannot answer in this window the peer is dropped rather than
	# admitted on a stale or unanswered request.
	scene_multiplayer.auth_timeout = NetworkConfig.auth_timeout()
	scene_multiplayer.auth_callback = _on_auth
	print(
		LOG_PREFIX
		+ "auth configured: callback_valid=%s timeout=%.1fs"
		% [str(scene_multiplayer.auth_callback.is_valid()), scene_multiplayer.auth_timeout]
	)
	scene_multiplayer.peer_authentication_failed.connect(_on_auth_failed)
	scene_multiplayer.peer_connected.connect(_on_peer_connected)
	scene_multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	registry.displaced_peer.connect(_on_displaced)

	var peer := ENetMultiplayerPeer.new()
	peer.set_bind_ip(_bound_address)
	var error := peer.create_server(_port, 32)
	if error != OK:
		push_error(LOG_PREFIX + "cannot listen on udp/%d: %s" % [_port, error_string(error)])
		get_tree().quit(3)
		return
	multiplayer.multiplayer_peer = peer
	_running = true
	_announce(
		"listening on udp/%d bind=%s server_id=%s auth_timeout=%.1fs"
		% [_port, _bound_address, _server_id, NetworkConfig.auth_timeout()]
	)
	server_ready.emit(_port)


## Report a lifecycle line on stdout and, when configured, to a readiness file.
##
## stdout is block-buffered when the process is redirected, so a supervisor that
## terminates the server can lose the very line it was waiting for. The file is
## written and closed immediately, which makes startup observable without
## depending on the process exiting cleanly.
func _announce(message: String) -> void:
	print(LOG_PREFIX + message)
	var path := OS.get_environment("GODOT_MULTIPLAYER_READY_FILE")
	if path == "":
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_line(message)
		file.close()


# ── authentication ─────────────────────────────────────────────────────────


## SceneMultiplayer auth callback: ``(peer_id, data) -> bool``.
##
## Returning false is deliberate. It leaves the peer in the authenticating
## state -- invisible to get_peers() and unable to do anything but exchange auth
## data -- while the ticket is validated. ``complete_auth`` is called later only
## if the backend vouches for the identity.
func _on_auth(peer_id: int, data: PackedByteArray) -> bool:
	print(LOG_PREFIX + "auth data from peer %d (%d bytes)" % [peer_id, data.size()])
	var parsed: Variant = JSON.parse_string(data.get_string_from_utf8())
	if not (parsed is Dictionary) or not (parsed as Dictionary).has("ticket"):
		_reject(peer_id, "MALFORMED_AUTH")
		return false
	var ticket := str((parsed as Dictionary)["ticket"])
	if _pending.has(peer_id):
		return false
	_pending[peer_id] = true
	_validate(peer_id, ticket)
	return false


func _validate(peer_id: int, ticket: String) -> void:
	print(LOG_PREFIX + "validating ticket for peer %d" % peer_id)
	var result: Dictionary = await bridge.consume(ticket, _server_id)
	var detail := str(result.get("detail", ""))
	if detail.length() > 120:
		detail = detail.substr(0, 120)
	print(
		LOG_PREFIX + "backend answered for peer %d: ok=%s error=%s detail=%s"
		% [
			peer_id,
			str(bool(result.get("ok", false))),
			str(result.get("error", "")),
			detail,
		]
	)
	# The peer may have gone away while the backend was answering.
	if not _running or not _has_peer(peer_id):
		_pending.erase(peer_id)
		return
	if not bool(result.get("ok", false)):
		_pending.erase(peer_id)
		_reject(peer_id, str(result.get("error", "REJECTED")))
		return

	registry.admit(peer_id, result)
	_pending.erase(peer_id)
	var scene_multiplayer := multiplayer as SceneMultiplayer
	var player_id := int(result.get("player_id", 0))
	var username := str(result.get("username", ""))
	print(
		LOG_PREFIX + "admitted peer %d as player %d (%s) room=%s"
		% [peer_id, player_id, username, str(result.get("room", ""))]
	)
	# The verified identity travels back on the authentication channel, which
	# is already established in both directions and needs no agreed node path.
	# A high-level rpc() would have to resolve to the same NodePath on both ends,
	# which the two scenes do not share.
	var verdict := JSON.stringify(
		{
			"accepted": true,
			"player_id": player_id,
			"username": username,
			"room": str(result.get("room", "campus")),
			"server_id": _server_id,
		}
	)
	scene_multiplayer.send_auth(peer_id, verdict.to_utf8_buffer())
	# Recorded *before* complete_auth, because complete_auth emits peer_connected
	# synchronously and that callback is what publishes this player. Set after, the
	# lookup there always misses and the roster stays permanently empty.
	_awaiting_connect[peer_id] = {
		"player_id": player_id,
		"username": username,
	}
	# complete_auth on both ends finishes the handshake; the client does the same
	# from its own auth callback when this message arrives.
	scene_multiplayer.complete_auth(peer_id)
	# The roster is published from _on_peer_connected, which is the first moment a
	# peer can actually receive a high-level RPC. Publishing earlier would silently
	# never arrive.
	peer_admitted.emit(peer_id, player_id, username)


func _reject(peer_id: int, reason: String) -> void:
	print(LOG_PREFIX + "rejected peer %d: %s" % [peer_id, reason])
	peer_rejected.emit(peer_id, reason)
	_awaiting_connect.erase(peer_id)
	link.server_forget_peer(peer_id)
	registry.release(peer_id)
	_pending.erase(peer_id)
	(multiplayer as SceneMultiplayer).disconnect_peer(peer_id)


func _on_auth_failed(peer_id: int) -> void:
	# Fired when a peer leaves the authenticating state without completing, which
	# covers both a rejected ticket and an expired auth_timeout.
	_pending.erase(peer_id)
	_awaiting_connect.erase(peer_id)
	link.server_forget_peer(peer_id)
	registry.release(peer_id)


func _has_peer(peer_id: int) -> bool:
	# Must consider both sets. A peer mid-handshake is in
	# get_authenticating_peers() and deliberately absent from get_peers(), which
	# is exactly the state this check runs in -- testing get_peers() alone would
	# always report "gone" and silently drop every valid admission.
	var scene_multiplayer := multiplayer as SceneMultiplayer
	return (
		scene_multiplayer.get_peers().has(peer_id)
		or scene_multiplayer.get_authenticating_peers().has(peer_id)
	)


# ── lifecycle ──────────────────────────────────────────────────────────────


func _on_peer_connected(peer_id: int) -> void:
	print(LOG_PREFIX + "peer %d authenticated" % peer_id)
	# Now that the peer is fully connected, publish it. The roster broadcast also
	# teaches this newcomer about everyone who was already here.
	var waiting: Dictionary = _awaiting_connect.get(peer_id, {})
	if not waiting.is_empty():
		_awaiting_connect.erase(peer_id)
		var admitted_player := int(waiting.get("player_id", 0))
		var identity := registry.identity_for(peer_id)
		link.server_track_player(
			peer_id, admitted_player, str(waiting.get("username", ""))
		)
		# Only now is the peer fully connected, so only now does it get an entity
		# to move. The identity and generation come from the registry, not the peer.
		if movement != null:
			movement.add_player(
				admitted_player,
				peer_id,
				int(identity.get("generation", -1)),
				str(identity.get("room", "campus")),
				str(waiting.get("character_code", "")),
			)


func _on_peer_disconnected(peer_id: int) -> void:
	var player_id := registry.player_for(peer_id)
	_pending.erase(peer_id)
	_awaiting_connect.erase(peer_id)
	# Republish before the registry entry goes: this is what makes every client
	# drop the leaving avatar in the same frame the server notices.
	link.server_forget_peer(peer_id)
	if player_id > 0:
		movement.remove_player(player_id, "disconnect")
	registry.release(peer_id)
	if player_id > 0:
		print(LOG_PREFIX + "peer %d (player %d) disconnected" % [peer_id, player_id])
		peer_left.emit(peer_id, player_id)
	else:
		print(LOG_PREFIX + "peer %d disconnected" % peer_id)


func _on_displaced(peer_id: int, player_id: int) -> void:
	# A newer session for this player won. Drop the older socket. registry
	# already ignored its release, so it cannot take the successor's entry.
	print(
		LOG_PREFIX + "superseding stale session for player %d (peer %d)"
		% [player_id, peer_id]
	)
	# Clears the mapping for the old socket only; the successor keeps the roster
	# entry because server_forget_peer only erases the entry it still owns.
	#
	# The entity is deliberately left alone. The successor already spawned its own
	# with its own generation, and the displaced socket can no longer drive it:
	# MovementAuthority refuses any packet whose connection generation no longer
	# matches. Dropping it here would instead delete the live player's body.
	link.server_forget_peer(peer_id)
	(multiplayer as SceneMultiplayer).disconnect_peer(peer_id)


# ── authenticated surface ──────────────────────────────────────────────────


## True only for a peer the backend vouched for.
func is_admitted(peer_id: int) -> bool:
	return registry.is_admitted(peer_id)


## Guard for any future gameplay RPC: refuses an unauthenticated caller.
func refuse_unless_admitted(peer_id: int) -> bool:
	if is_admitted(peer_id):
		return true
	_reject(peer_id, "NOT_AUTHENTICATED")
	return false


func room_members(room: String) -> Array:
	return registry.room_members(room)


func player_count() -> int:
	return registry.peer_count()


func authenticating_count() -> int:
	return (multiplayer as SceneMultiplayer).get_authenticating_peers().size()


func is_running() -> bool:
	return _running


func shutdown() -> void:
	if not _running:
		return
	print(LOG_PREFIX + "shutting down with %d admitted peer(s)" % registry.peer_count())
	for peer_id in registry.admitted_peer_ids():
		(multiplayer as SceneMultiplayer).disconnect_peer(peer_id)
	registry.clear()
	if link != null:
		link.server_clear_roster()
	if movement != null:
		movement.clear_all()
	_pending.clear()
	_awaiting_connect.clear()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	_running = false
	print(LOG_PREFIX + "stopped")


func _notification(what: int) -> void:
	# PREDELETE fires during teardown, after the multiplayer API has already been
	# detached; touching it then throws. Only a clean shutdown closes state.
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		shutdown()