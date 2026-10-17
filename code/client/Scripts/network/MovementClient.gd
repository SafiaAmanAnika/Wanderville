extends Node2D
class_name MovementClient
## The client half of server-authoritative campus movement.
##
## The client owns three things and nothing else: the keyboard, a predicted local
## position, and the interpolation of other players. It does not own position --
## every authoritative position arrives from the server in a snapshot, and the
## local prediction is continuously reconciled against it.
##
## **Prediction** runs the same ``move_and_slide()`` against the same campus
## collision at the same speed, so local movement feels immediate without the
## client deciding anything the server has to agree with. On a snapshot the
## client's prediction for that exact input sequence is compared with the
## authoritative result:
##
##   * within a few pixels -- leave it alone, which is the overwhelmingly common
##     case and is what stops the view jittering;
##   * a small drift -- bleed it off gradually;
##   * a large divergence -- snap, because that is a real disagreement (a wall the
##     client thought it cleared, or a lost input packet) and easing into it would
##     leave the player visibly out of step with the server.
##
## Prediction can therefore never override a server decision: when the server says
## a position is impossible, the client ends up at the server's position.

signal local_position_changed(position: Vector2)
signal remote_joined(player_id: int)
signal remote_left(player_id: int)
signal snapshot_received(tick: int, entity_count: int)

## The game's own speed, identical to MovementAuthority.SPEED and to
## Scripts/chara_player.gd. Prediction is only useful if it matches the server's
## integration exactly.
const SPEED := 300.0

const INPUT_HZ := 25.0

## Error below which the client does nothing at all.
const RECONCILE_DEADZONE := 2.0
## Error above which the client snaps, because easing would look like rubber-banding.
const RECONCILE_SNAP := 48.0
## Fraction of a small error corrected per snapshot.
const RECONCILE_BLEED := 0.35

## How many snapshots may arrive with no sign of a remote avatar before it is
## dropped as stale.
const STALE_SNAPSHOTS := 40

var input_enabled := true
## Set by a headless test to drive movement without a keyboard.
var scripted_input := Vector2.ZERO

var local: CharacterBody2D
var player_id := 0

var _link: NetworkLink
var _sequence := 0
var _input_accumulator := 0.0
var _predicted: Dictionary = {}
var _last_state: Dictionary = {}
var _remotes: Dictionary = {}
var _roster: Dictionary = {}
var _missed: Dictionary = {}
var _corrections := 0
var _snaps := 0
var _snapshots := 0
var _inputs_sent := 0
var _last_facing := 2
var _label_font: Font
var _started := false


func setup(link: NetworkLink, character_code: String = "") -> void:
	_link = link


## Build the same collision world the server simulates against, so local
## prediction collides identically and reconciliation has nothing to argue about.
##
## The arena option must match the server's, which is why the test harness passes
## GODOT_MOVEMENT_ARENA through to both ends rather than only to the server.
func build_collision_world(parent: Node) -> int:
	if OS.get_environment("GODOT_MOVEMENT_ARENA") == "1":
		return MovementArena.build(parent).get_child_count()
	return CampusCollision.build(parent).get_child_count()


func start(local_player_id: int, character_code: String) -> void:
	player_id = local_player_id
	_label_font = WoodPanel.PIXEL_FONT
	_spawn_local(character_code)
	_link.roster_received.connect(_on_roster)
	# The link re-emits the snapshot RPC as a plain signal, so this node never has
	# to be on the RPC path itself.
	if not _link.received_snapshots.is_connected(_on_snapshot):
		_link.received_snapshots.connect(_on_snapshot)
	_started = true
	# Claim a character for presentation. Validated server-side against the real
	# character table; appearance carries no authority.
	#
	# Deferred until the server peer is actually reachable: _on_admitted runs
	# inside this client's auth callback, and the server has not finished its own
	# handshake at that point, so an rpc_id(1, ...) here is rejected with
	# "Attempt to call RPC with unknown peer ID: 1" and the claim is lost.
	if character_code != "":
		_announce_when_connected(character_code)


func _announce_when_connected(character_code: String) -> void:
	if multiplayer.get_peers().has(1):
		_link.announce_character.rpc_id(1, character_code)
		return
	var once := func(_id: int) -> void:
		_link.announce_character.rpc_id(1, character_code)
	multiplayer.peer_connected.connect(once, CONNECT_ONE_SHOT)


func _spawn_local(character_code: String) -> void:
	var code := character_code if character_code != "" else "farmer_female"
	if not Global.CHARACTER_SCENES.has(code):
		code = "farmer_female"
	local = Global.get_character_scene(code).instantiate() as CharacterBody2D
	local.name = "LocalPlayer"
	add_child(local)
	# Disabled so the character's own controller cannot also move it; the only
	# thing that moves this body is this node's prediction, which is then
	# reconciled against the server.
	#
	# set_physics_process(false), not PROCESS_MODE_DISABLED: the latter takes the
	# body out of the physics space, so local prediction would stop colliding and
	# move_and_slide() would fail outright.
	local.set_physics_process(false)
	local.remove_from_group("player")
	local.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	local.collision_layer = MovementAuthority.LAYER_PLAYER
	local.collision_mask = MovementAuthority.LAYER_WORLD
	local.global_position = _spawn_point()
	local.velocity = Vector2.ZERO
	var sprite := CharacterPresentation.sprite_of(local)
	if sprite != null:
		sprite.process_mode = Node.PROCESS_MODE_ALWAYS


## Matches the server's deterministic ring, so both ends start in the same place
## without a round trip.
func _spawn_point() -> Vector2:
	var slots := 8
	var index := absi(player_id) % slots
	var angle := TAU * float(index) / float(slots)
	var ring := 260.0 if index > 0 else 0.0
	return CampusCollision.CAMPUS_SPAWN + Vector2(cos(angle), sin(angle)) * ring


# ── input and prediction ───────────────────────────────────────────────────


func _physics_process(delta: float) -> void:
	if local == null or not is_instance_valid(local) or not _started:
		return
	var direction := _read_input()
	if direction != Vector2.ZERO:
		_last_facing = MovementProtocol.facing_from_direction(direction)
	local.velocity = direction * SPEED
	local.move_and_slide()
	_predicted[_sequence] = local.global_position
	local_position_changed.emit(local.global_position)

	_input_accumulator += delta
	if _input_accumulator >= 1.0 / INPUT_HZ:
		_input_accumulator = 0.0
		_send_input(direction)


func _read_input() -> Vector2:
	if not input_enabled:
		return Vector2.ZERO
	if scripted_input != Vector2.ZERO:
		return scripted_input.normalized()
	var axis := Vector2(
		Input.get_axis("ui_left", "ui_right"),
		Input.get_axis("ui_up", "ui_down")
	)
	return axis.normalized() if axis != Vector2.ZERO else Vector2.ZERO


func _send_input(direction: Vector2) -> void:
	_sequence += 1
	var packet := MovementProtocol.encode_input(
		_sequence, direction, _last_facing, direction != Vector2.ZERO
	)
	_link.submit_input.rpc_id(1, packet)
	_inputs_sent += 1
	# Only a short window of predictions is kept; the server's answer always
	# arrives within a snapshot or two, so anything older is dead weight.
	if _predicted.size() > 240:
		for key in _predicted.keys().slice(0, 120):
			_predicted.erase(key)


# ── snapshots ──────────────────────────────────────────────────────────────


func _on_snapshot(packet: PackedByteArray) -> void:
	var snapshot := MovementProtocol.decode_snapshot(packet)
	if snapshot.is_empty():
		return
	_snapshots += 1
	snapshot_received.emit(int(snapshot["tick"]), (snapshot["entities"] as Array).size())
	for entry in snapshot["entities"]:
		var id := int(entry["player_id"])
		_last_state[id] = entry
		if id == player_id:
			_reconcile(entry)
		else:
			_apply_remote(id, entry)


## Reconcile the local prediction against what the server decided.
func _reconcile(state: Dictionary) -> void:
	if local == null or not is_instance_valid(local):
		return
	var authoritative := Vector2(float(state["x"]), float(state["y"]))
	var seq := int(state.get("last_seq", -1))
	var predicted: Variant = _predicted.get(seq)
	if predicted is Vector2:
		# Drop predictions the server has now answered.
		for key in _predicted.keys():
			if int(key) <= seq:
				_predicted.erase(key)
	var error := authoritative - local.global_position
	var distance := error.length()
	if distance <= RECONCILE_DEADZONE:
		return
	if distance >= RECONCILE_SNAP:
		local.global_position = authoritative
		_snaps += 1
	else:
		local.global_position += error * RECONCILE_BLEED
	_corrections += 1


func _apply_remote(id: int, state: Dictionary) -> void:
	_missed[id] = 0
	if _remotes.has(id):
		(_remotes[id] as RemoteAvatar).apply_snapshot(state)
		return
	# A snapshot for somebody not in the roster is not spawned on trust: the roster
	# is the reliable, authoritative membership list, and a snapshot alone could be
	# a late packet about a player who has already left.
	if not _roster.has(id):
		return
	var entry: Dictionary = _roster[id]
	_spawn_remote(id, entry, Vector2(float(state["x"]), float(state["y"])))


func _spawn_remote(id: int, entry: Dictionary, position: Vector2) -> void:
	var avatar := RemoteAvatar.new()
	avatar.name = "Remote_%d" % id
	add_child(avatar)
	avatar.setup(
		id,
		str(entry.get("username", "Player")),
		str(entry.get("character_code", "")),
		position,
		_label_font,
	)
	_remotes[id] = avatar
	remote_joined.emit(id)


func _on_roster(entries: Array) -> void:
	_roster.clear()
	var mine := player_id
	for entry in entries:
		var id := int(entry.get("player_id", 0))
		if id == mine:
			# Never render an avatar of yourself, which is what stops a reconnect
			# or a duplicated roster entry from producing two copies.
			continue
		_roster[id] = entry
	# Anything the server no longer lists is removed: this is what makes a
	# disconnect disappear, and what keeps a stale session from lingering.
	for id in _remotes.keys():
		if not _roster.has(id):
			_drop_remote(id)


func _drop_remote(id: int) -> void:
	if not _remotes.has(id):
		return
	var avatar: RemoteAvatar = _remotes[id]
	_remotes.erase(id)
	_missed.erase(id)
	_last_state.erase(id)
	if avatar != null and is_instance_valid(avatar):
		avatar.queue_free()
	remote_left.emit(id)


func _process(_delta: float) -> void:
	# Stale cleanup: a player whose snapshots stop arriving entirely (a half-open
	# connection, say) is removed rather than frozen on screen forever.
	for id in _remotes.keys():
		_missed[id] = int(_missed.get(id, 0)) + 1
		if int(_missed[id]) > STALE_SNAPSHOTS:
			_drop_remote(id)


# ── reporting, for tests and the on-screen display ─────────────────────────


func authoritative_position() -> Vector2:
	var state: Dictionary = _last_state.get(player_id, {})
	if state.is_empty():
		return Vector2.ZERO
	return Vector2(float(state["x"]), float(state["y"]))


func remote_ids() -> Array:
	return _remotes.keys()


func remote_avatar(id: int) -> RemoteAvatar:
	return _remotes.get(id, null)


func correction_count() -> int:
	return _corrections


func snap_count() -> int:
	return _snaps


func snapshot_count() -> int:
	return _snapshots


func inputs_sent() -> int:
	return _inputs_sent


func local_position() -> Vector2:
	return local.global_position if local != null and is_instance_valid(local) else Vector2.ZERO