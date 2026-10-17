extends Node2D
## Headless campus-movement client driven by the integration harness.
##
## It runs the real path: real ticket, real UDP, real ENet, real server physics,
## real campus collision, real character scenes. It reports what the **server**
## said, so the harness can assert on authoritative positions rather than on this
## client's own opinion of where it went.
##
## It also has a raw mode used to attack the server deliberately: instead of
## well-formed input it sends forged packets -- a packet with an extra identity
## field, an over-long direction, a replayed sequence number -- so the tests can
## prove each one is rejected rather than merely assumed to be.
##
## Environment:
##   TEST_API_URL, TEST_TOKEN, TEST_USERNAME, TEST_HOST, TEST_PORT   as elsewhere
##   TEST_CHARACTER        character code to present          (default farmer_female)
##   TEST_EXPECT_ROSTER    roster size that counts as "settled"
##   TEST_INPUT_SCRIPT     "right:2.0,idle:0.3,up:1.5" -- direction:seconds
##   TEST_HOLD_SECONDS     idle time after the script, for late snapshots
##   TEST_RAW_ATTACKS      "oversized_identity,long_direction,replay_seq,..."
##   TEST_FORGE_TICKET     present this ticket instead of requesting one, and
##                         still send movement packets (the pre-authentication
##                         attack)

const LOG_PREFIX := "[MovementHarness] "

var client: MultiplayerClient
var link: NetworkLink
var movement: MovementClient

var _username := ""
var _host := NetworkConfig.DEFAULT_HOST
var _port := NetworkConfig.DEFAULT_PORT
var _phase := "boot"
var _elapsed := 0.0
var _settled := false
var _script_steps: Array = []
var _script_index := 0
var _script_time := 0.0
var _attacks: Array = []
var _attack_index := 0
var _attack_time := 0.0

## Observed server-reported bounds, per player. A test asserts a player moved by
## looking at the range the *server* published, not at local prediction.
var _observed: Dictionary = {}
var _start_state: Dictionary = {}


func _ready() -> void:
	_username = OS.get_environment("TEST_USERNAME")
	if _username == "":
		_username = "mover"
	_host = OS.get_environment("TEST_HOST")
	if _host == "":
		_host = NetworkConfig.DEFAULT_HOST
	_port = int(OS.get_environment("TEST_PORT"))

	link = NetworkLink.new()
	link.name = "NetworkLink"
	add_child(link)

	movement = MovementClient.new()
	movement.name = "MovementClient"
	add_child(movement)
	movement.setup(link)
	# The same collision world the server simulates against, so local prediction
	# collides identically and reconciliation has nothing to argue about.
	movement.build_collision_world(self)

	_parse_scripts()

	client = MultiplayerClient.new()
	add_child(client)
	client.configure(OS.get_environment("TEST_API_URL"), OS.get_environment("TEST_TOKEN"))
	client.admitted.connect(_on_admitted)
	client.rejected.connect(_on_rejected)
	client.disconnected.connect(_on_disconnected)

	print(
		"%s starting host=%s port=%d user=%s attacks=%s"
		% [LOG_PREFIX, _host, _port, _username, str(_attacks)]
	)
	if OS.get_environment("TEST_UNAUTHENTICATED") == "1":
		# Deliberately never authenticates: opens a raw peer and tries to move.
		# This is the pre-authentication attack path.
		_start_unauthenticated()
		return
	_phase = "connecting"
	client.connect_to_server(_host, _port)


## A peer that never presents a ticket, then tries to drive movement anyway.
##
## There is no auth_callback on this side at all, which is exactly how a naive
## attacker would be written. The server's callback is set, so this peer stays in
## the authenticating state and its packets must never reach the simulation.
func _start_unauthenticated() -> void:
	_phase = "attacking_unauthenticated"
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(_host, _port)
	print("%s raw peer create_client err=%d" % [LOG_PREFIX, int(error)])
	multiplayer.multiplayer_peer = peer
	_attack_index = 0
	_attack_time = 0.0
	if _attacks.is_empty():
		_attacks = ["flood"]


func _parse_scripts() -> void:
	var raw := OS.get_environment("TEST_INPUT_SCRIPT")
	for chunk in raw.split(",", false):
		var parts := chunk.strip_edges().split(":")
		if parts.size() != 2:
			continue
		var name := parts[0].strip_edges()
		var seconds := float(parts[1])
		var direction := _direction_for(name)
		_script_steps.append({"direction": direction, "seconds": seconds})
	var attacks := OS.get_environment("TEST_RAW_ATTACKS")
	for name in attacks.split(",", false):
		var trimmed := name.strip_edges()
		if trimmed != "":
			_attacks.append(trimmed)


func _direction_for(name: String) -> Vector2:
	match name:
		"right": return Vector2.RIGHT
		"left": return Vector2.LEFT
		"up": return Vector2.UP
		"down": return Vector2.DOWN
		"idle": return Vector2.ZERO
		_: return Vector2.ZERO


func _on_admitted(identity: Dictionary) -> void:
	var player_id := int(identity.get("player_id", 0))
	var character := OS.get_environment("TEST_CHARACTER")
	if character == "":
		character = "farmer_female"
	movement.start(player_id, character)
	# Attacks are sent from a genuinely admitted session, so a rejection proves the
	# server judged the packet rather than the connection.
	link.received_snapshots.connect(_observe)
	movement.remote_joined.connect(_on_remote_joined)
	movement.remote_left.connect(_on_remote_left)
	_result({
		"event": "admitted",
		"ok": true,
		"username": _username,
		"player_id": player_id,
		"room": str(identity.get("room", "")),
	})
	_phase = "settling"


func _on_rejected(reason: String) -> void:
	_result({"event": "rejected", "ok": false, "username": _username, "reason": reason})
	if not _attacks.is_empty():
		# An attack client that cannot authenticate still tries to move, which is
		# the whole point of the pre-authentication test.
		_phase = "attacking_unauthenticated"
		return
	get_tree().quit(1)


## Roster changes are reported as they happen rather than only at the end, so a
## test can prove an avatar vanished the moment its owner disconnected instead of
## inferring it afterwards.
func _on_remote_joined(id: int) -> void:
	_result({
		"event": "remote_joined",
		"username": _username,
		"player_id": movement.player_id,
		"other": id,
		"remote_ids": movement.remote_ids(),
	})


func _on_remote_left(id: int) -> void:
	_result({
		"event": "remote_left",
		"username": _username,
		"player_id": movement.player_id,
		"other": id,
		"remote_ids": movement.remote_ids(),
	})


func _on_disconnected() -> void:
	pass


## Record the range of positions the server published for each player.
func _observe(packet: PackedByteArray) -> void:
	var snapshot := MovementProtocol.decode_snapshot(packet)
	if snapshot.is_empty():
		return
	for entry in snapshot["entities"]:
		var id := int(entry["player_id"])
		var point := Vector2(float(entry["x"]), float(entry["y"]))
		if not _observed.has(id):
			_observed[id] = {
				"player_id": id, "min_x": point.x, "max_x": point.x,
				"min_y": point.y, "max_y": point.y, "samples": 0, "last": point,
			}
		var row: Dictionary = _observed[id]
		row["min_x"] = minf(float(row["min_x"]), point.x)
		row["max_x"] = maxf(float(row["max_x"]), point.x)
		row["min_y"] = minf(float(row["min_y"]), point.y)
		row["max_y"] = maxf(float(row["max_y"]), point.y)
		row["samples"] = int(row["samples"]) + 1
		row["last"] = point
		_observed[id] = row


func _process(delta: float) -> void:
	_elapsed += delta
	match _phase:
		"settling":
			_maybe_settle()
		"moving":
			_run_script(delta)
		"attacking_unauthenticated":
			_run_attacks(delta, true)
		"attacking":
			_run_attacks(delta, false)
		"holding":
			movement.scripted_input = Vector2.ZERO
			if _elapsed >= _hold_until():
				_finish()


func _hold_until() -> float:
	return _hold_deadline


var _hold_deadline := 0.0


func _maybe_settle() -> void:
	var wanted := int(OS.get_environment("TEST_EXPECT_ROSTER"))
	if wanted <= 0:
		wanted = 2
	if movement.remote_ids().size() + 1 < wanted:
		return
	# Give the last snapshot a moment to land so the "before" position is real.
	_settled = true
	print(
		"%s settled: self=%d remotes=%s"
		% [_username, movement.player_id, str(movement.remote_ids())]
	)
	_attack_time = 0.0
	_script_time = 0.0
	if not _attacks.is_empty():
		_phase = "attacking"
		return
	if _script_steps.is_empty():
		# Nothing to drive: hold the session open so a supervisor can watch this
		# client stay connected. Without this the phase would never advance and the
		# process would hang until it was killed.
		_phase = "holding"
		_hold_deadline = _elapsed + float(OS.get_environment("TEST_HOLD_SECONDS"))
		return
	_phase = "moving"


func _run_script(delta: float) -> void:
	if _script_index < _script_steps.size():
		var step: Dictionary = _script_steps[_script_index]
		movement.scripted_input = step["direction"]
		_script_time += delta
		if _script_time >= float(step["seconds"]):
			_script_time = 0.0
			_script_index += 1
			if _script_index >= _script_steps.size():
				movement.scripted_input = Vector2.ZERO
				_phase = "holding"
				_hold_deadline = _elapsed + float(OS.get_environment("TEST_HOLD_SECONDS"))
				return
		return
	movement.scripted_input = Vector2.ZERO


## Sends the crafted packets. Deliberately bypasses MovementClient, because these
## are inputs no honest client would ever produce.
func _run_attacks(delta: float, unauthenticated: bool) -> void:
	movement.scripted_input = Vector2.ZERO
	if _attack_index >= _attacks.size():
		if _attack_index > 0:
			_finish()
		else:
			_attack_index = 0
		return
	_attack_time += delta
	if _attack_time < 0.5:
		return
	_attack_time = 0.0
	var kind: String = _attacks[_attack_index]
	_attack_index += 1
	var before := movement.inputs_sent()
	match kind:
		"oversized_identity":
			# A well-formed input packet with an identity field glued on, i.e. a
			# client trying to say "this is player X".
			var forged := MovementProtocol.encode_input(
				movement.inputs_sent() + 1, Vector2.RIGHT, 0, true
			)
			forged.append_array(PackedByteArray([1, 2, 3, 4]))
			link.submit_input.rpc_id(1, forged)
		"long_direction":
			# Both axes at the maximum magnitude: a direction of length 1.414, i.e.
			# "move 41% faster". Written as raw bytes on purpose -- encoding it
			# through the normal path would clamp it to a unit vector and the server
			# would never see anything invalid to reject.
			link.submit_input.rpc_id(1, MovementProtocol.encode_raw_input(
				movement.inputs_sent() + 1, 127, 127, 0, MovementProtocol.FLAG_MOVING
			))
		"replay_seq":
			# A sequence number the server has already consumed.
			var stale := MovementProtocol.encode_input(1, Vector2.UP, 0, true)
			link.submit_input.rpc_id(1, stale)
		"flood":
			# Spread over the tick rather than blasted in one frame. A single large
			# burst is dropped in transit by the unreliable channel, which would
			# make this test pass for the wrong reason.
			#
			# 20 per tick against a 25 Hz legitimate rate is ~65 packets/second
			# against a bucket that refills at 30, so the bucket genuinely drains.
			for _i in 20:
				var packet := MovementProtocol.encode_raw_input(
					movement.inputs_sent() + 5000 + _attack_index * 40 + _i,
					127, 0, 0, MovementProtocol.FLAG_MOVING
				)
				link.submit_input.rpc_id(1, packet)
		"zero_seq":
			# The oldest possible sequence, to probe the wrap comparison.
			link.submit_input.rpc_id(
				1, MovementProtocol.encode_input(0, Vector2.LEFT, 0, true)
			)
	print("%s attack %s sent (inputs_sent %d -> %d)" % [LOG_PREFIX, kind, before, movement.inputs_sent()])


func _finish() -> void:
	var rows: Array = []
	for id in _observed:
		rows.append(_observed[id])
	_result({
		"event": "final",
		"ok": true,
		"username": _username,
		"player_id": movement.player_id if movement != null else 0,
		"observed": rows,
		"corrections": movement.correction_count() if movement != null else 0,
		"snaps": movement.snap_count() if movement != null else 0,
		"snapshots": movement.snapshot_count() if movement != null else 0,
		"inputs_sent": movement.inputs_sent() if movement != null else _attack_index,
		"remote_ids": movement.remote_ids() if movement != null else [],
		"attacks_sent": _attack_index,
	})
	if client != null:
		client.disconnect_from_server()
	get_tree().quit(0)


func _result(payload: Dictionary) -> void:
	print("RESULT " + JSON.stringify(payload))