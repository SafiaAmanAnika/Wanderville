extends RefCounted
class_name PeerRegistry
## Maps ENet peer ids to verified backend player ids, and refuses to guess.
##
## The one rule this type exists to enforce: a peer id only ever becomes a
## player id through the backend's signed answer to a ticket consumption. There
## is no path that accepts an identity from a client, because "which player is
## this peer" is the single question a hostile peer would like to answer for
## somebody else.
##
## Duplicate sessions get one deterministic policy: **the newest connection
## replaces the older one, and the older peer's registry entry is torn down
## under the displaced connection's generation.** Replacing rather than rejecting
## keeps a player from being locked out by a stale connection they cannot see;
## the generation check is what stops the displaced socket from later deleting
## its successor's state.

var _lock := Mutex.new()
## peer_id -> { player_id, generation, username, room, admitted_at }
var _peers: Dictionary = {}
## player_id -> peer_id, so a duplicate session can find the peer to displace.
var _by_player: Dictionary = {}
## Monotonic counter so a superseded connection can be recognised and ignored.
var _generation := 0


func admit(peer_id: int, identity: Dictionary) -> int:
	## Record a backend-verified identity for ``peer_id``.
	##
	## Returns the generation this admission owns. A previous session for the
	## same player is removed first, and its peer id is returned through
	## ``displaced_peer`` via the signal so the caller can disconnect it.
	var generation := 0
	var displaced := -1
	_lock.lock()
	_generation += 1
	generation = _generation
	var player_id := int(identity.get("player_id", 0))
	var existing := int(_by_player.get(player_id, -1))
	if existing != -1 and existing != peer_id:
		displaced = existing
		_peers.erase(existing)
	_peers[peer_id] = {
		"player_id": player_id,
		"generation": generation,
		"username": str(identity.get("username", "")),
		"room": str(identity.get("room", "campus")),
		"owned_world_id": int(identity.get("owned_world_id", 0)),
		"current_world_id": int(identity.get("current_world_id", 0)),
		"session_mode": str(identity.get("session_mode", "OWNER")),
		"admitted_at": Time.get_ticks_msec(),
	}
	_by_player[player_id] = peer_id
	_lock.unlock()
	if displaced != -1:
		displaced_peer.emit(displaced, player_id)
	return generation


signal displaced_peer(peer_id: int, player_id: int)


func is_admitted(peer_id: int) -> bool:
	_lock.lock()
	var known := _peers.has(peer_id)
	_lock.unlock()
	return known


func player_for(peer_id: int) -> int:
	_lock.lock()
	var row: Dictionary = _peers.get(peer_id, {})
	_lock.unlock()
	return int(row.get("player_id", 0))


func identity_for(peer_id: int) -> Dictionary:
	_lock.lock()
	var row: Dictionary = _peers.get(peer_id, {})
	_lock.unlock()
	return row.duplicate()


func generation_for(peer_id: int) -> int:
	_lock.lock()
	var row: Dictionary = _peers.get(peer_id, {})
	_lock.unlock()
	return int(row.get("generation", -1))


func peer_for_player(player_id: int) -> int:
	_lock.lock()
	var peer := int(_by_player.get(player_id, -1))
	_lock.unlock()
	return peer


func room_members(room: String) -> Array:
	_lock.lock()
	var found: Array = []
	for peer_id in _peers:
		var row: Dictionary = _peers[peer_id]
		if str(row.get("room", "")) == room:
			found.append({
				"peer_id": peer_id,
				"player_id": int(row.get("player_id", 0)),
				"username": str(row.get("username", "")),
			})
	_lock.unlock()
	return found


## Remove a peer, but only if it still owns the session it was admitted under.
##
## Without the generation check a connection that has already been superseded
## could disconnect and delete its successor's registry entry.
func release(peer_id: int, generation: int = -1) -> bool:
	_lock.lock()
	var row: Dictionary = _peers.get(peer_id, {})
	if row.is_empty():
		_lock.unlock()
		return false
	if generation >= 0 and int(row.get("generation", -1)) != generation:
		_lock.unlock()
		return false
	var player_id := int(row.get("player_id", 0))
	_peers.erase(peer_id)
	if int(_by_player.get(player_id, -1)) == peer_id:
		_by_player.erase(player_id)
	_lock.unlock()
	return true


func peer_count() -> int:
	_lock.lock()
	var count := _peers.size()
	_lock.unlock()
	return count


func admitted_players() -> Array:
	_lock.lock()
	var players: Array = []
	for peer_id in _peers:
		players.append(int(_peers[peer_id].get("player_id", 0)))
	_lock.unlock()
	return players


## Snapshot of the currently admitted peer ids, for iteration.
func admitted_peer_ids() -> Array:
	_lock.lock()
	var ids: Array = _peers.keys()
	_lock.unlock()
	return ids


func clear() -> void:
	_lock.lock()
	_peers.clear()
	_by_player.clear()
	_lock.unlock()