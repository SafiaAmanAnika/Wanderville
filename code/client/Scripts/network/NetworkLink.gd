extends Node
class_name NetworkLink
## The single RPC endpoint shared by the dedicated server and every client.
##
## **Why this node exists, and why it is a direct child of the scene root.**
##
## A Godot high-level RPC carries a NodePath that is resolved against
## ``SceneMultiplayer.root_path``, and the receiver looks that path up
## *locally*. The server scene's root is called ``DedicatedServer`` while the
## client scene's root is called something else entirely, so with the default
## ``root_path`` of ``/root`` the two ends compute ``/root/DedicatedServer/NetworkLink``
## and ``/root/RenderedClient/NetworkLink`` and never meet. The packet arrives,
## the node is not found, and the call is silently dropped.
##
## That is not a guess -- it was measured with two real processes before this
## subsystem existed: with the default root_path an ``unreliable_ordered`` ping
## was sent and never received; calling ``set_root_path()`` to each side's own
## scene root made the identical packet arrive both ways.
##
## So every side points ``root_path`` at its own scene root in ``_ready``. The
## link then resolves to the same *relative* path (``NetworkLink``) on both ends,
## which is all the wire carries.
##
## Channels, per the ``@rpc`` annotations below. Both ends must agree exactly.
##
##   channel 0, reliable               lifecycle and roster
##   channel 1, unreliable_ordered     movement input and snapshots
##
## Movement is replaceable data: a dropped snapshot is superseded by the next one
## 1/15s later, so retransmitting it only adds latency. Lifecycle changes are not
## replaceable and use reliable delivery.

## Emitted on a client when the server publishes a roster.
signal roster_received(entries: Array)

## Emitted on the server for each inbound movement packet and character claim.
##
## The @rpc methods below are thin and re-emit these, because an RPC method is not
## a signal and cannot be connected to; the handler subscribes here instead.
signal input_received(packet: PackedByteArray)
signal character_announced(character_code: String)

## Emitted on a client for each authoritative snapshot the server published.
signal received_snapshots(packet: PackedByteArray)

## player_id -> roster entry, on the server only.
var _roster: Dictionary = {}
## peer_id -> player_id, so a disconnect can be resolved without trusting a peer.
var _peer_players: Dictionary = {}


func _ready() -> void:
	# Must happen before any peer connects: the server side sets its root path in
	# _ready, which runs before any client can be admitted.
	(multiplayer as SceneMultiplayer).set_root_path(get_parent().get_path())
	print(
		"[NetworkLink] ready root_path=%s path=%s"
		% [multiplayer.get_root_path(), str(get_path())]
	)


## Evaluated on demand, never cached: a client has no multiplayer peer yet when
## it reaches ``_ready``, and a cached answer would report every client as a
## server.
func is_server() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()


# ── movement transport (unreliable_ordered, channel 1) ─────────────────────
#
# Declared here so the channel and transfer mode are configured identically on
# both ends. MovementAuthority (server) and MovementClient (clients) are wired
# to these same methods.


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func submit_input(packet: PackedByteArray) -> void:
	input_received.emit(packet)


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func receive_snapshot(packet: PackedByteArray) -> void:
	received_snapshots.emit(packet)


# ── lifecycle transport (reliable, channel 0) ───────────────────────────────


@rpc("any_peer", "call_remote", "reliable", 0)
func announce_character(character_code: String) -> void:
	character_announced.emit(character_code)


@rpc("authority", "call_remote", "reliable", 0)
func receive_roster(entries: Array) -> void:
	roster_received.emit(entries)


# ── server-side roster bookkeeping ─────────────────────────────────────────


## Server only. Record an admitted player and republish the roster.
##
## Call this only once the peer has fully connected. A peer that is still in the
## authenticating state cannot be sent high-level RPCs, so announcing it earlier
## produces a roster that silently never reaches it.
func server_track_player(peer_id: int, player_id: int, username: String) -> void:
	if not is_server():
		return
	_roster[player_id] = {
		"player_id": player_id,
		"username": username,
		"peer_id": peer_id,
	}
	_peer_players[peer_id] = player_id
	broadcast_roster()


## Server only. Stop tracking a peer and republish, which is what removes a
## remote avatar on every client at once.
func server_forget_peer(peer_id: int) -> void:
	if not is_server():
		return
	var player_id := int(_peer_players.get(peer_id, 0))
	if player_id == 0:
		return
	_peer_players.erase(peer_id)
	# Ownership-checked: a displaced session must not delete the successor's
	# entry, or a reconnect would erase the live player instead.
	if int(_roster.get(player_id, {}).get("peer_id", -1)) == peer_id:
		_roster.erase(player_id)
	broadcast_roster()


func server_set_character(player_id: int, character_code: String) -> void:
	if not is_server():
		return
	if not _roster.has(player_id):
		return
	_roster[player_id]["character_code"] = character_code
	broadcast_roster()


func server_player(player_id: int) -> Dictionary:
	return _roster.get(player_id, {})


func roster_entries() -> Array:
	return _roster.values()


func server_player_count() -> int:
	return _roster.size()


## Drop all roster state, so a restarted server publishes an empty roster
## instead of resurrecting players from a previous run's memory.
func server_clear_roster() -> void:
	if not is_server():
		return
	_roster.clear()
	_peer_players.clear()


## Send the whole roster to everyone. The roster is tiny at campus scale, and a
## full republish means a joining or leaving client cannot be left with a
## half-applied delta that disagrees with everyone else's view.
func broadcast_roster() -> void:
	if not is_server():
		return
	var entries := roster_entries()
	print(
		"[NetworkLink] publishing roster of %d to %d peer(s)"
		% [entries.size(), multiplayer.get_peers().size()]
	)
	receive_roster.rpc(entries)