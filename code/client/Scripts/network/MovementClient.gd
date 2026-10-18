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
## Correction backlog is drained at no more than this many units per second, so no
## single frame can move the body further than this times delta. Well above the
## 300 units/second movement speed, so convergence stays ahead of the error.
const CORRECTION_MAX_SPEED := 450.0

## How many snapshots may arrive with no sign of a remote avatar before it is
## dropped as stale.
## Seconds without a snapshot before a remote is treated as gone. Generous on
## purpose: see _process(). A real disconnect is handled by the roster long before
## this fires.
const STALE_SECONDS := 3.0

var input_enabled := true
var input_gate: Callable
var gameplay_presentation := false
var _awaiting_spawn := false
## When true the client transmits nothing at all after settling, not even neutral
## packets. Used to exercise the server's input-expiry path directly, which is a
## different condition from "client says I am idle".
var input_silent := false
## Set by a headless test to drive movement without a keyboard.
var scripted_input := Vector2.ZERO

var local: CharacterBody2D
var player_id := 0

var _link: NetworkLink
var _sequence := 0
var _input_accumulator := 0.0
var _predicted: Dictionary = {}
## True when the scene already provides collision, so none is built here.
var _uses_scene_collision := false
var _last_state: Dictionary = {}
var _remotes: Dictionary = {}
var _roster: Dictionary = {}
var _missed: Dictionary = {}
var _corrections := 0
## Corrections that pulled a moving player backwards, and how far in total.
## Small corrections waiting to be applied, spread across frames.
var _pending_correction := Vector2.ZERO
## Largest correction distance applied in any single frame.
var _max_step := 0.0
var _back_nudges := 0
var _back_nudge_distance := 0.0
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
## Use collision that already exists in the scene.
##
## In the real game the campus map is in the tree carrying its own CollisionLayer,
## so building the harvested world here as well would put every lake and border
## into the physics space twice and instantiate map.tscn a second time. This marks
## the scene as the collision source so build_collision_world stands down.
func adopt_scene_collision() -> void:
	_uses_scene_collision = true


func build_collision_world(parent: Node) -> int:
	if _uses_scene_collision:
		return 0
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


## Drive a player body that already exists in the real game scene.
##
## The normal game already has a local CharacterBody2D, its own camera and its own
## animation. Spawning a second one here would put two characters on the campus and
## two things trying to move this one. So this adopts the existing body instead of
## creating anything, and the caller is responsible for stopping the body's own
## controller first.
##
## Everything after the spawn is identical to start(): the same prediction, the
## same reconciliation, the same remote avatars. Only ownership of the local body
## differs.
func start_adopting(body: CharacterBody2D, local_player_id: int, character_code: String) -> void:
	if body == null or not is_instance_valid(body):
		push_error("[MovementClient] start_adopting needs a live body")
		return
	stop()
	local = body
	_awaiting_spawn = true
	gameplay_presentation = true
	player_id = local_player_id
	_label_font = WoodPanel.PIXEL_FONT

	# The body belongs to the real scene, so its collision layers are already
	# whatever the game uses. What must go is its own controller: two things moving
	# one body is the duplicate-movement bug this whole path exists to avoid.
	local.set_physics_process(false)
	local.velocity = Vector2.ZERO
	var adopted_sprite := CharacterPresentation.sprite_of(local)
	if adopted_sprite != null:
		adopted_sprite.process_mode = Node.PROCESS_MODE_ALWAYS

	_link.roster_received.connect(_on_roster)
	if not _link.received_snapshots.is_connected(_on_snapshot):
		_link.received_snapshots.connect(_on_snapshot)
	_started = true
	if character_code != "":
		_announce_when_connected(character_code)


func stop() -> void:
	_started = false
	_sequence = 0
	_input_accumulator = 0.0
	_predicted.clear()
	_last_state.clear()
	_roster.clear()
	_pending_correction = Vector2.ZERO
	for id in _remotes.keys():
		_drop_remote(id)
	if is_instance_valid(local):
		local.velocity = Vector2.ZERO
	if _link != null:
		if _link.roster_received.is_connected(_on_roster):
			_link.roster_received.disconnect(_on_roster)
		if _link.received_snapshots.is_connected(_on_snapshot):
			_link.received_snapshots.disconnect(_on_snapshot)


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
	if local == null or not is_instance_valid(local) or not _started or _awaiting_spawn:
		return
	var direction := _read_input()
	if direction != Vector2.ZERO:
		_last_facing = MovementProtocol.facing_from_direction(direction)
	local.velocity = direction * SPEED
	local.move_and_slide()
	if _pending_correction.length() > 0.01:
		var step := _pending_correction.limit_length(CORRECTION_MAX_SPEED * delta)
		local.global_position += step
		# How far the body actually moved this frame, corrections included. A
		# visual jump shows up here as a large single-frame displacement.
		_max_step = maxf(_max_step, step.length())
		_pending_correction -= step

	# Drive the local player's own presentation here, because nothing else can.
	#
	# _spawn_local calls set_physics_process(false) so the character's own
	# controller cannot fight the prediction that actually moves it. For the
	# chara_player family that is merely a disabled switch, but player.gd reads
	# the keyboard and calls _update_animation from its _physics_process, so
	# switching physics off silently switched the local sprite off with it: it
	# stood on one frame, facing whatever it spawned on, for as long as the
	# session lasted. Remote avatars were unaffected because RemoteAvatar._process
	# calls CharacterPresentation.play for them.
	#
	# This is the same call the remote makes, with the same arguments, so the two
	# cannot drift apart again. It is presentation only and comes after
	# move_and_slide: nothing here can influence where the player is.
	if not gameplay_presentation or (local.get("_busy") != true and local.get("fishing") != true):
		CharacterPresentation.play(local, direction != Vector2.ZERO, direction, _last_facing)
		if gameplay_presentation and local.has_method("_dir_from_vector") and direction != Vector2.ZERO:
			local.set("facing", local._dir_from_vector(direction))

	_predicted[_sequence] = local.global_position
	local_position_changed.emit(local.global_position)

	_input_accumulator += delta
	if _input_accumulator >= 1.0 / INPUT_HZ:
		_input_accumulator = 0.0
		if input_silent:
			# Transmit nothing at all. The server must stop this player on its own
			# and must keep the peer connected -- silence is not a disconnect.
			return
		_send_input(direction)


func _read_input() -> Vector2:
	if not input_enabled or (input_gate.is_valid() and not input_gate.call()):
		return Vector2.ZERO
	if scripted_input != Vector2.ZERO:
		return scripted_input.normalized()
	var axis := Vector2(
		Input.get_axis("ui_left", "ui_right"),
		Input.get_axis("ui_up", "ui_down")
	)
	return axis.normalized() if axis != Vector2.ZERO else Vector2.ZERO


func _send_input(direction: Vector2) -> void:
	if not multiplayer.get_peers().has(1):
		return
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
	if _awaiting_spawn:
		local.global_position = authoritative
		_awaiting_spawn = false
		return

	# Reconcile against this client's own most recent unacknowledged prediction,
	# not against wherever the body happens to be right now.
	#
	# The old code measured the error as authoritative minus the current position,
	# which folds two different things together: genuine divergence between client
	# and server, and the distance the client has legitimately travelled since the
	# server answered. At 300 units a second and 25Hz input, that second term is
	# large by construction, so every 15Hz snapshot reported a correction of
	# several units that had nothing wrong with it, 35 percent of which was applied
	# straight back to the body. Fifteen small nudges a second is the jitter.
	#
	# The prediction for the newest sequence the server has not yet answered is
	# where the client believes it should already be, so subtracting that leaves
	# only real disagreement. When the two agree, which is the normal case, the
	# error is nil and nothing moves at all.
	var target := authoritative
	var newest := -1
	var predicted: Variant = _predicted.get(seq)
	if predicted is Vector2:
		# Drop predictions the server has now answered.
		for key in _predicted.keys():
			if int(key) <= seq:
				_predicted.erase(key)
	for key in _predicted.keys():
		if int(key) > seq:
			newest = maxi(newest, int(key))
	if newest >= 0:
		if gameplay_presentation:
			# Preserve unacknowledged motion, never replace the server position
			# with a client position. Unknown acknowledgements use the server.
			if predicted is Vector2:
				target = authoritative + (_predicted[newest] - predicted)
		else:
			target = _predicted[newest]
	var error := target - local.global_position
	var distance := error.length()
	if distance <= RECONCILE_DEADZONE:
		return
	if distance >= RECONCILE_SNAP:
		# A large divergence is resolved at once on purpose. This is what a wall
		# deflection, a respawn or a room transition looks like, and easing any of
		# those would drag the player away from where the server actually put them.
		local.global_position = target
		_pending_correction = Vector2.ZERO
		_snaps += 1
	else:
		# Small corrections are queued rather than applied, because applying one
		# immediately is what reads as a twitch.
		#
		# An empty unacknowledged-input buffer does not mean the server position is
		# current: it means the server has caught up with everything sent so far, and
		# the body has since moved on. The two are therefore compared across
		# different moments, and a residual of a few units is arithmetic rather than
		# drift. Applied instantly, thirty of those a second became visible shaking.
		#
		# Queuing them keeps the convergence but spreads it over frames, so no single
		# frame moves the body further than CORRECTION_MAX_SPEED allows. It still
		# converges: the queue drains every frame and is never discarded, so server
		# disagreement is not hidden, merely delivered over a few frames instead of
		# one. A backlog large enough to be a real divergence is flushed immediately
		# by the snap branch above rather than being smoothed into a lie.
		_pending_correction += error
		if _pending_correction.length() >= RECONCILE_SNAP:
			local.global_position += _pending_correction
			_pending_correction = Vector2.ZERO
	_corrections += 1
	# A correction that pulls a moving player backwards is the one the eye reads as
	# jitter, so it is counted apart from ordinary corrections instead of being
	# averaged into them.
	var heading := local.velocity
	if heading.length() > 1.0:
		if error.normalized().dot(heading.normalized()) < 0.0:
			_back_nudges += 1
			_back_nudge_distance += distance


func _apply_remote(id: int, state: Dictionary) -> void:
	_missed[id] = Time.get_ticks_msec() / 1000.0
	if _remotes.has(id):
		(_remotes[id] as RemoteAvatar).apply_snapshot(state)
		return
	# A snapshot for somebody not in the roster is not spawned on trust: the roster
	# is the reliable, authoritative membership list, and a snapshot alone could be
	# a late packet about a player who has already left.
	if not _roster.has(id):
		return
	var entry: Dictionary = _roster[id]
	if gameplay_presentation and not entry.has("character_code"):
		return
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
	if gameplay_presentation:
		avatar.apply_gameplay_scale(str(entry.get("character_code", "")))
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
	#
	# Measured in seconds, not in frames. This used to count rendered frames and
	# compare the count against STALE_SNAPSHOTS, which quietly made the threshold
	# a function of the frame rate and of the snapshot rate at the same time.
	# Snapshots arrive at 15Hz, so four frames is a healthy margin at 60fps, and
	# the old limit of forty frames allowed only about two thirds of a second of
	# silence. Three rendered Vulkan windows sharing one laptop GPU produce gaps
	# longer than that on their own, so an avatar was destroyed while its owner
	# sat right there holding still, and the very next snapshot rebuilt it. That
	# surfaced as one remote_joined event per blip, which is exactly the flicker
	# that made a reconnect look like it produced several avatars.
	#
	# A genuine disconnect does not wait for this: the server calls
	# server_forget_peer, which republishes the roster without the player, and
	# _on_roster drops the avatar immediately. This path is only the backstop for
	# a socket that dies without the server noticing, so it can afford to be
	# generous without delaying a real leave.
	var now := Time.get_ticks_msec() / 1000.0
	for id in _remotes.keys():
		if now - float(_missed.get(id, now)) > STALE_SECONDS:
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


## Backward nudges and the distance they covered, so the jitter can be measured.
func back_nudge_stats() -> Dictionary:
	return {"count": _back_nudges, "distance": _back_nudge_distance, "max_step": _max_step}


func snap_count() -> int:
	return _snaps


func snapshot_count() -> int:
	return _snapshots


func inputs_sent() -> int:
	return _inputs_sent


func local_position() -> Vector2:
	return local.global_position if local != null and is_instance_valid(local) else Vector2.ZERO
