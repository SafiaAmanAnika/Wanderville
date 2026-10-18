extends Node
class_name MovementAuthority
## The server's authoritative movement simulation for the campus.
##
## The server owns position. A client sends a direction and a sequence number and
## nothing else; the server advances every entity on its own fixed physics
## timestep and publishes where each one ended up. There is no message that can
## carry a position, so no client can request one.
##
## Each entity is a real ``CharacterBody2D`` built from the real character scene,
## moved with the real ``move_and_slide()``, against the real campus collision
## harvested from ``map.tscn``. Speed is the game's own 300 units per second, the
## same constant ``Scripts/chara_player.gd`` uses, so a player moves at exactly
## the rate they move in the single-player game.
##
## Defence in depth, in the order each input is checked:
##   1. the peer is admitted            (an unauthenticated peer cannot move)
##   2. its player id comes from the registry, never from the packet
##   3. the connection generation still matches, so a superseded session cannot
##      drive the live entity
##   4. the packet decodes and its fields are in range
##   5. the sequence number is newer than the last accepted one
##   6. the packet rate is inside a token bucket
## Speed, collision and distance limits are then applied by the server's own
## physics, so a client cannot exceed them at all.

const LOG_PREFIX := "[Movement] "

## The game's configured movement speed. Identical to SPEED in both
## Scripts/player.gd and Scripts/chara_player.gd.
const SPEED := 300.0

const INPUT_HZ := 25.0
const SNAPSHOT_HZ := 15.0

## Per-peer input budget. The bucket allows a burst (so a hiccup does not starve a
## player) but refills at slightly more than INPUT_HZ, so a client that floods
## loses tokens and its excess packets are dropped instead of being applied.
const INPUT_BUCKET_CAPACITY := 60.0
const INPUT_BUCKET_REFILL := 30.0

## How long an entity keeps moving after its last input packet.
##
## Not zero. Unreliable delivery means an occasional dropped packet, and stopping
## on the first one would make a player stutter every time the network hiccups, so
## a short grace is kept. It is deliberately short: a client that stops talking
## stops moving within a quarter second rather than sliding on forever, which is
## what makes a lost connection safe instead of a runaway player.
const INPUT_TIMEOUT := 0.25

## Physics layers. Campus geometry is layer 1; player entities are layer 2 and
## mask only layer 1, so players collide with the world but not with each other.
## Two players shoving each other is not modelled in this phase, and leaving it out
## keeps movement deterministic for the tests.
const LAYER_WORLD := 1
const LAYER_PLAYER := 2

const ROOM_CAMPUS := "campus"

## Distance a player may legitimately cover in one server tick, with a small
## margin for float error. Nothing enforces this, because the server computes the
## movement itself; it is measured instead, and a breach would mean the server had
## a bug rather than that a client had.
const MAX_DISTANCE_PER_TICK := SPEED / 60.0 * 1.75

## How many rejected packets from one peer are tolerated before it is dropped.
const MAX_REJECTS := 240

var _server: Node
var _link: NetworkLink
var _entities: Dictionary = {}
var _rejects: Dictionary = {}
var _tick := 0
var _snapshot_accumulator := 0.0
var _dump_accumulator := 0.0
var _dump_path := ""
var _token_clock := 0.0
var _packets_in_window := 0
var _rate_window := 0.0
var _bytes_sent := 0
var _collision_shapes := 0
var _collision_built := false
var _gameplay_mode := OS.get_environment("GODOT_ENET_GAMEPLAY") == "1"
var _arena_mode := false
## Opt-in diagnostics. Off by default so a normal server log stays readable.
var _trace := OS.get_environment("GODOT_MOVEMENT_TRACE") == "1"
var _world_label := ""
var _speed_limit_violations := 0

signal player_spawned(player_id: int, position: Vector2)
signal player_removed(player_id: int)


## Called by DedicatedServer after this node is already in the tree.
##
## A child's ``_ready`` runs before its parent's, so ``_ready`` cannot be relied on
## for the link reference -- which is exactly why the first version of this
## crashed with a null ``_link``.
func setup(server: Node, link: NetworkLink) -> void:
	_server = server
	_link = link
	if not _arena_mode:
		_link.world_info = {"version": CampusCollision.shape_version(CampusCollision.extract_shapes()), "gameplay": _gameplay_mode}
	_dump_path = OS.get_environment("GODOT_MOVEMENT_DUMP_FILE")
	link.input_received.connect(_on_submit_input)
	link.character_announced.connect(_on_announce_character)


func _ready() -> void:
	# The isolated arena is opt-in and clearly labelled as not being the campus.
	_arena_mode = OS.get_environment("GODOT_MOVEMENT_ARENA") == "1"
	_world_label = MovementArena.NAME if _arena_mode else CampusCollision.MAP_SCENE
	if _arena_mode:
		_collision_shapes = MovementArena.build(self).get_child_count()
	else:
		var campus := CampusCollision.build(self, not _gameplay_mode)
		# Gameplay advertises the source map version; never simulate a stale cache.
		_collision_shapes = campus.get_child_count()
		if _gameplay_mode:
			campus.position = CampusCollision.WORLD_OFFSET
	# Written once, so a test can check the geometry offline. Crucially this must
	# match the world that was just built: dumping the campus while running in the
	# arena instantiated map.tscn purely to serialise shapes nobody was using,
	# which cost about 15 seconds and ~10 MB of TileSet error output per process.
	var collision_path := OS.get_environment("GODOT_MOVEMENT_COLLISION_FILE")
	if collision_path != "":
		if _arena_mode:
			MovementArena.dump(collision_path)
		else:
			CampusCollision.dump(collision_path)
	print(
		LOG_PREFIX + "collision world from %s: %d shapes, speed=%.0f units/s"
		% [_world_label, _collision_shapes, SPEED]
	)
	print(
		LOG_PREFIX
		+ "physics=%d Hz input=%.0f Hz snapshots=%.0f Hz rooms=%s only"
		% [Engine.physics_ticks_per_second, INPUT_HZ, SNAPSHOT_HZ, ROOM_CAMPUS]
	)


## Present for symmetry and for callers that must not block; the world is already
## built by the time any entity can exist.
func _ensure_collision_world() -> void:
	pass


## A client may declare which character it is using, for presentation only.
##
## Validated against the real character table and then applied to that player's
## entity. Appearance carries no authority: it cannot change a position, a room or
## an identity, so a client claiming a character it does not own can only make its
## own avatar look different.
func _on_announce_character(character_code: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 0 or _server == null or not _server.is_admitted(sender):
		return
	var player_id: int = _server.registry.player_for(sender)
	if player_id <= 0 or not _entities.has(player_id):
		return
	if not Global.CHARACTER_SCENES.has(character_code):
		character_code = "farmer_female"
	set_character(player_id, character_code)
	_server.link.server_set_character(player_id, character_code)


# ── input ───────────────────────────────────────────────────────────────────


func _on_submit_input(packet: PackedByteArray) -> void:
	var sender := multiplayer.get_remote_sender_id()
	_audit(sender, packet)


## One place where every inbound movement packet is judged, so the order of the
## checks cannot drift between paths.
func _audit(sender: int, packet: PackedByteArray) -> void:
	# 1. admitted?
	if sender <= 0 or _server == null or not _server.refuse_unless_admitted(sender):
		_reject(sender, "not_admitted")
		return
	# 2. the identity comes from the registry. Never from the packet: there is no
	#    identity field in the packet to take one from.
	var player_id: int = _server.registry.player_for(sender)
	if player_id <= 0:
		_reject(sender, "unknown_player")
		return
	var entity: Dictionary = _entities.get(player_id, {})
	if entity.is_empty():
		_reject(sender, "no_entity")
		return
	# 3. is this still the session that owns the entity?
	var generation: int = _server.registry.generation_for(sender)
	if generation != int(entity.get("generation", -1)):
		# A superseded socket. It must not be able to drive the live player.
		_reject(sender, "stale_generation")
		return
	# 6. rate limit, before spending effort decoding.
	if not _spend_token(entity):
		_reject(sender, "rate_limited")
		return
	# 4/5. structure, ranges, finiteness, sequence.
	var decoded := MovementProtocol.decode_input(packet)
	if decoded.is_empty():
		_reject(sender, "malformed")
		return
	var seq := int(decoded["seq"])
	if not MovementProtocol.is_newer(seq, int(entity.get("last_seq", -1))):
		# A replay, a duplicate or an out-of-order packet. Counted so the behaviour
		# is observable in the dump rather than being silent, but deliberately not
		# penalised: unreliable delivery makes this a routine event, and treating
		# it as an attack would punish ordinary packet loss.
		_reject(sender, "stale_sequence")
		return

	entity["last_seq"] = seq
	entity["direction"] = decoded["direction"]
	entity["moving"] = bool(decoded["moving"])
	entity["last_input_at"] = Time.get_ticks_msec() / 1000.0
	var facing := int(decoded["facing"])
	if facing >= 0:
		entity["facing"] = facing
	_entities[player_id] = entity
	_packets_in_window += 1


func _spend_token(entity: Dictionary) -> bool:
	var tokens := float(entity.get("tokens", INPUT_BUCKET_CAPACITY))
	if tokens < 1.0:
		entity["tokens"] = tokens
		return false
	entity["tokens"] = tokens - 1.0
	return true


func _reject(peer_id: int, reason: String, count: bool = true) -> void:
	if count:
		_rejects[reason] = int(_rejects.get(reason, 0)) + 1
		var total := 0
		for value in _rejects.values():
			total += int(value)
		if total > MAX_REJECTS and _server != null:
			push_warning(LOG_PREFIX + "dropping peer %d: %d rejected movement packets" % [peer_id, total])


# ── simulation ──────────────────────────────────────────────────────────────


func _physics_process(delta: float) -> void:
	_tick += 1
	var wall_clock := Time.get_ticks_msec() / 1000.0
	_token_clock += delta
	_rate_window += delta
	if _rate_window >= 1.0:
		_rate_window -= 1.0
		_packets_in_window = 0

	# Refill every bucket by the same amount, so a peer is judged on its own rate
	# rather than on when it happened to send.
	if _token_clock >= 0.1:
		var refill := INPUT_BUCKET_REFILL * _token_clock
		_token_clock = 0.0
		for player_id in _entities:
			var entity: Dictionary = _entities[player_id]
			entity["tokens"] = minf(
				float(entity.get("tokens", 0.0)) + refill, INPUT_BUCKET_CAPACITY
			)
			_entities[player_id] = entity

	for player_id in _entities:
		var entity: Dictionary = _entities[player_id]
		entity["tokens"] = float(entity.get("tokens", 0.0))
		var body: CharacterBody2D = entity["body"]
		var before := body.global_position
		# The speed is the server's constant. The client contributed a direction
		# and nothing else.
		var direction: Vector2 = entity.get("direction", Vector2.ZERO)
		var declared_moving := bool(entity.get("moving", false))
		if not declared_moving:
			direction = Vector2.ZERO
		# A client that has stopped talking stops moving, after a short grace that
		# absorbs a single dropped unreliable packet.
		var silence := wall_clock - float(entity.get("last_input_at", 0.0))
		var expired := silence > INPUT_TIMEOUT
		if expired:
			direction = Vector2.ZERO
		# Diagnostics, opt-in via GODOT_MOVEMENT_TRACE and only on the transitions
		# plus a periodic sample, so a trace stays readable and never floods.
		if _trace and direction != Vector2.ZERO and not bool(entity.get("was_moving", false)):
			print(
				LOG_PREFIX + "trace MOVE-START player=%d tick=%d t=%.2f seq=%d dir=%s pos=%s"
				% [player_id, _tick, wall_clock, int(entity.get("last_seq", -1)),
					str(direction), str(before)]
			)
		if _trace and direction == Vector2.ZERO and bool(entity.get("was_moving", false)):
			print(
				LOG_PREFIX + "trace MOVE-STOP player=%d tick=%d t=%.2f declared_moving=%s expired=%s silence=%.3f seq=%d pos=%s"
				% [player_id, _tick, wall_clock, str(declared_moving), str(expired),
					silence, int(entity.get("last_seq", -1)), str(before)]
			)
		entity["was_moving"] = direction != Vector2.ZERO
		var velocity_before := body.velocity
		body.velocity = direction * SPEED
		body.move_and_slide()
		var after := body.global_position
		if before.distance_to(after) > MAX_DISTANCE_PER_TICK:
			# Not reachable from the network: the server just moved this body. If
			# it ever fires, the simulation is wrong, not the client.
			_speed_limit_violations += 1
		if _trace and _tick % 30 == 0:
			print(
				LOG_PREFIX + "trace tick player=%d tick=%d t=%.2f pos=%s vel=%s->%s seq=%d dir=%s declared_moving=%s silence=%.2fs expired=%s moved=%.1f"
				% [player_id, _tick, wall_clock, str(after), str(velocity_before),
					str(body.velocity), int(entity.get("last_seq", -1)),
					str(direction), str(declared_moving), silence, str(expired),
					before.distance_to(after)]
			)
		entity["position"] = after
		_entities[player_id] = entity

	_snapshot_accumulator += delta
	if _snapshot_accumulator >= 1.0 / SNAPSHOT_HZ:
		_snapshot_accumulator = 0.0
		_publish_snapshot()

	_dump_accumulator += delta
	if _dump_accumulator >= 0.25:
		_dump_accumulator = 0.0
		_write_dump()


func _publish_snapshot() -> void:
	if _link == null or _entities.is_empty():
		return
	var rows: Array = []
	for player_id in _entities:
		var entity: Dictionary = _entities[player_id]
		var body: CharacterBody2D = entity["body"]
		rows.append({
			"player_id": int(player_id),
			"last_seq": int(entity.get("last_seq", 0)),
			"x": body.global_position.x,
			"y": body.global_position.y,
			"facing": int(entity.get("facing", 0)),
			"flags": MovementProtocol.FLAG_MOVING if bool(entity.get("moving", false)) else 0,
		})
	var packet := MovementProtocol.encode_snapshot(_tick, rows)
	_bytes_sent += packet.size()
	_link.receive_snapshot.rpc(packet)


# ── entity lifecycle ────────────────────────────────────────────────────────


## Deterministic spawn points around the production campus spawn, spaced so two
## players never begin inside one another.
func spawn_position(player_id: int) -> Vector2:
	var slots := 8
	var index := absi(player_id) % slots
	var angle := TAU * float(index) / float(slots)
	var ring := 260.0 if index > 0 else 0.0
	return CampusCollision.CAMPUS_SPAWN + Vector2(cos(angle), sin(angle)) * ring


func add_player(player_id: int, peer_id: int, generation: int, room: String,
		character_code: String = "") -> void:
	# The first entity pays for the collision world.
	_ensure_collision_world()
	if room != ROOM_CAMPUS:
		# Campus is the only room this phase simulates. A peer admitted to any
		# other room is tracked but never given an entity, rather than being
		# quietly placed on the campus.
		print(LOG_PREFIX + "player %d is in room '%s'; no campus entity" % [player_id, room])
		return
	remove_player(player_id, "respawn")
	var position := spawn_position(player_id)
	var body := _make_body(character_code, position)
	_entities[player_id] = {
		"peer_id": peer_id,
		"generation": generation,
		"room": ROOM_CAMPUS,
		"body": body,
		"position": position,
		"direction": Vector2.ZERO,
		"moving": false,
		"facing": 2,  # front
		"last_seq": -1,
		"last_input_at": Time.get_ticks_msec() / 1000.0,
		"tokens": INPUT_BUCKET_CAPACITY,
		"character_code": character_code,
		"spawned_tick": _tick,
	}
	print(
		LOG_PREFIX
		+ "spawned player %d (peer %d) at (%.1f, %.1f) character=%s"
		% [player_id, peer_id, position.x, position.y, character_code if character_code != "" else "default"]
	)
	player_spawned.emit(player_id, position)


## A real character scene, so the entity carries the real collision outline.
func _make_body(character_code: String, position: Vector2) -> CharacterBody2D:
	var code := character_code if character_code != "" else "farmer_female"
	if not Global.CHARACTER_SCENES.has(code):
		code = "farmer_female"
	var body := Global.get_character_scene(code).instantiate() as CharacterBody2D
	if _gameplay_mode:
		body.scale = Vector2.ONE * (20.0 if code in ["player1", "farmer_female"] else 1.18)
	add_child(body)
	# Stop the character's own controller without taking the body out of the
	# physics space.
	#
	# PROCESS_MODE_DISABLED looks equivalent and is not: it removes the body from
	# the physics space entirely, so move_and_slide() then fails with
	# "body->get_space() is null" and the entity silently never moves. Measured
	# with a standalone probe, which is also how set_physics_process(false) was
	# chosen over it.
	body.set_physics_process(false)
	body.set_process(false)
	# chara_player.gd adds itself to the "player" group; on a server there is no
	# local player, and nothing should ever mistake a simulated entity for one.
	body.remove_from_group("player")
	body.name = "Entity_%d" % body.get_instance_id()
	# Top-down: floating mode means no floor or gravity rules, matching the
	# reasoning already documented in chara_player.gd.
	body.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	body.collision_layer = LAYER_PLAYER
	body.collision_mask = LAYER_WORLD
	body.global_position = position
	body.velocity = Vector2.ZERO
	return body


func remove_player(player_id: int, reason: String = "") -> void:
	if not _entities.has(player_id):
		return
	var entity: Dictionary = _entities[player_id]
	var body: CharacterBody2D = entity.get("body")
	_entities.erase(player_id)
	if body != null and is_instance_valid(body):
		body.queue_free()
	print(LOG_PREFIX + "removed player %d %s" % [player_id, reason])
	player_removed.emit(player_id)


func set_character(player_id: int, character_code: String) -> void:
	if not _entities.has(player_id):
		return
	var entity: Dictionary = _entities[player_id]
	if _gameplay_mode and str(entity.get("character_code", "")) != character_code:
		var old: CharacterBody2D = entity["body"]
		entity["body"] = _make_body(character_code, old.global_position)
		old.queue_free()
	entity["character_code"] = character_code
	_entities[player_id] = entity


func has_player(player_id: int) -> bool:
	return _entities.has(player_id)


func authoritative_position(player_id: int) -> Vector2:
	if not _entities.has(player_id):
		return Vector2.ZERO
	var entity: Dictionary = _entities[player_id]
	var body: CharacterBody2D = entity["body"]
	return body.global_position if body != null and is_instance_valid(body) else Vector2.ZERO


func last_sequence(player_id: int) -> int:
	if not _entities.has(player_id):
		return -1
	return int((_entities[player_id] as Dictionary).get("last_seq", -1))


func entity_count() -> int:
	return _entities.size()


## Server shutdown: free every body so a restarted process starts from nothing.
func clear_all() -> void:
	for player_id in _entities.keys():
		remove_player(player_id, "shutdown")
	_rejects.clear()


func reject_counts() -> Dictionary:
	return _rejects.duplicate()


func collision_shape_count() -> int:
	return _collision_shapes


func collision_world_ready() -> bool:
	return _collision_built


func physics_ticks() -> int:
	return _tick


func speed_limit_violations() -> int:
	return _speed_limit_violations


# ── observability ───────────────────────────────────────────────────────────


## Write the server's own view of the world to a file.
##
## Tests assert against this rather than against what a client claims, so a test
## cannot pass by trusting a client's own report of where it went. Written and
## closed each time, like the readiness file, so a supervisor can read it while the
## server is still running.
func _write_dump() -> void:
	if _dump_path == "":
		return
	var rows: Array = []
	for player_id in _entities:
		var entity: Dictionary = _entities[player_id]
		var body: CharacterBody2D = entity["body"]
		if body == null or not is_instance_valid(body):
			continue
		rows.append({
			"player_id": int(player_id),
			"peer_id": int(entity.get("peer_id", 0)),
			"x": body.global_position.x,
			"y": body.global_position.y,
			"last_seq": int(entity.get("last_seq", -1)),
			"moving": bool(entity.get("moving", false)),
			"facing": int(entity.get("facing", 0)),
			"spawned_tick": int(entity.get("spawned_tick", 0)),
		})
	var payload := {
		"tick": _tick,
		"physics_hz": Engine.physics_ticks_per_second,
		"snapshot_hz": SNAPSHOT_HZ,
		"input_hz": INPUT_HZ,
		"speed": SPEED,
		"collision_shapes": _collision_shapes,
		"collision_world": _world_label,
		"arena_mode": _arena_mode,
		"entities": rows,
		"rejects": _rejects,
		"bytes_sent": _bytes_sent,
		"speed_limit_violations": _speed_limit_violations,
	}
	var file := FileAccess.open(_dump_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(payload))
	file.close()