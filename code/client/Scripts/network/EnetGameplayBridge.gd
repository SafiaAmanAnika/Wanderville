extends Node
class_name EnetGameplayBridge
## Opt-in normal-world movement. WebSocket still carries gameplay services.
## The dedicated server must also use GODOT_ENET_GAMEPLAY=1.

## How long the bridge will wait for ENet to admit this player before handing
## movement back to the standard WebSocket path. Bounded on purpose: without a
## deadline a server that never answers leaves the player standing on a body
## whose own controller was switched off, which reads as a frozen game rather
## than as a failed experimental transport.
const ATTACH_TIMEOUT_MS := 15000

var movement: MovementClient
var client: MultiplayerClient
var link: NetworkLink
var active := false
var _player_body: CharacterBody2D
var _phase := "off"
var _version := ""
var _retry_at := 0
var _handshake_deadline := 0
var _attach_deadline := 0
var _previous_root: NodePath
var _status: Label
## True once the bridge has handed movement back to the legacy path. Every
## recovery step is idempotent and gated on this, so a burst of failure signals
## cannot restore the same body twice.
var _fell_back := false
## True once this bridge has actually taken the body's physics over, so a
## recovery only touches a body it changed.
var _body_prepared := false
var _saved_body_layer := 1
var _saved_body_mask := 1
var _saved_body_motion := CharacterBody2D.MOTION_MODE_FLOATING
## TileMapLayer -> original collision_enabled, restored on fallback.
var _saved_tiles: Dictionary = {}

func attach(body: CharacterBody2D) -> void:
	if active or body == null:
		return
	_previous_root = (multiplayer as SceneMultiplayer).root_path
	active = true
	_player_body = body
	_saved_body_layer = body.collision_layer
	_saved_body_mask = body.collision_mask
	_saved_body_motion = body.motion_mode
	# A visitor's world is another player's farm. The dedicated server simulates
	# the campus only, so admitting a visitor would freeze them with no entity.
	# The room is a server decision, so if it says this player is visiting, stay
	# on the standard connection from the very first frame.
	if GameState.current_world_id() > 0:
		_use_legacy("private farm uses its isolated world connection")
		return
	_body_prepared = true
	body.set_physics_process(false)
	body.velocity = Vector2.ZERO
	APIClient.realtime.external_movement = true
	var world := get_parent()
	var map := world.get_node("Map") as Node2D
	_version = CampusCollision.live_version(map)
	if map.global_position != CampusCollision.WORLD_ORIGIN or map.scale != CampusCollision.MAP_SCALE or map.rotation != 0.0:
		_fail("Campus transform does not match the dedicated server.")
		return
	# Shared geometry currently includes static polygons, not TileSet physics.
	# Disable only tile collision on these runtime instances in ENet mode.
	# The previous value is kept so a fallback can put the map back exactly as
	# the rest of the game expects it.
	for tile in map.find_children("*", "TileMapLayer", true, false):
		_saved_tiles[tile] = tile.collision_enabled
		tile.collision_enabled = false
	link = NetworkLink.new()
	link.name = "NetworkLink"
	world.add_child(link)
	link.world_received.connect(_on_world)
	movement = MovementClient.new()
	movement.name = "EnetMovement"
	world.add_child(movement)
	movement.setup(link)
	movement.adopt_scene_collision()
	movement.input_gate = _input_allowed
	body.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	# The real game's interaction Area2Ds (water, fishing, the sign board, the
	# farm zone) all use Godot's default mask of layer 1, and the single-player
	# body sits on layer 1. Overwriting the layer with LAYER_PLAYER alone left
	# the player invisible to every one of them, so movement worked while no
	# prompt or menu ever opened. Keeping layer 1 as well as the player layer on
	# the client's own body restores every interaction without changing the
	# server, whose entities stay on LAYER_PLAYER so they never shove each other.
	body.collision_layer = MovementAuthority.LAYER_WORLD | MovementAuthority.LAYER_PLAYER
	body.collision_mask = MovementAuthority.LAYER_WORLD
	CharacterPresentation.prepare_gameplay(body)
	client = MultiplayerClient.new()
	add_child(client)
	client.admitted.connect(_on_admitted)
	client.rejected.connect(_fail)
	client.disconnected.connect(_on_disconnected)
	var layer := CanvasLayer.new()
	add_child(layer)
	_status = Label.new()
	_status.position = Vector2(16, 70)
	_status.add_theme_color_override("font_color", Color.YELLOW)
	layer.add_child(_status)
	_attach_deadline = Time.get_ticks_msec() + ATTACH_TIMEOUT_MS
	_connect()

func _connect() -> void:
	_phase = "connecting"
	_status.text = "Experimental ENet: connecting..."
	client.configure(APIClient.base_url, Global.token)
	client.connect_to_server(NetworkConfig.host(), NetworkConfig.port())

func _on_admitted(identity: Dictionary) -> void:
	if int(identity.get("player_id", 0)) != Global.player_id:
		_fail("Admission identity does not match the logged-in player.")
		return
	_phase = "checking campus"
	_handshake_deadline = Time.get_ticks_msec() + 10000

func _on_world(info: Dictionary) -> void:
	if _phase != "checking campus":
		return
	if str(info.get("version", "")) != _version or not bool(info.get("gameplay", false)):
		_fail("Incompatible campus/server mode. Start a matching gameplay server.")
		return
	movement.start_adopting(_player_body, Global.player_id, Global.selected_character)
	_phase = "admitted"
	# The campus is the only room the dedicated server simulates. If the
	# authoritative WebSocket room later says this player moved into a farm,
	# ENet can no longer move them and must hand back to the standard path.
	if not APIClient.realtime.room_changed.is_connected(_on_room_changed):
		APIClient.realtime.room_changed.connect(_on_room_changed)
	_status.text = "Experimental ENet: connected (local/trusted network)"
	print("[EnetGameplay] admitted player=%d collision=%s" % [Global.player_id, _version])

func _input_allowed() -> bool:
	if _phase != "admitted" or not Global.is_logged_in() or not APIClient.realtime.connected:
		return false
	if GameState.menu_open or GameState.social_open or get_viewport().gui_get_focus_owner() is LineEdit:
		return false
	if _player_body.has_method("network_input_allowed"):
		return _player_body.network_input_allowed()
	return true

func _on_disconnected() -> void:
	movement.stop()
	client.disconnect_from_server()
	_phase = "reconnecting"
	_status.text = "Experimental ENet: disconnected; reconnecting..."
	_retry_at = Time.get_ticks_msec() + 1500
	# A reconnect gets its own bounded window; there is no state in which the
	# player waits forever on a transport that is not answering.
	_attach_deadline = Time.get_ticks_msec() + ATTACH_TIMEOUT_MS

func reconnect() -> void:
	if movement == null:
		return
	_on_disconnected()

func _process(_delta: float) -> void:
	if _fell_back:
		return
	if _phase == "reconnecting" and Time.get_ticks_msec() >= _retry_at:
		_connect()
	elif _phase == "checking campus" and Time.get_ticks_msec() > _handshake_deadline:
		_fail("The server did not provide a campus version.")
	elif (
		_phase == "connecting" or _phase == "checking campus" or _phase == "reconnecting"
	) and Time.get_ticks_msec() > _attach_deadline:
		_fail("The movement server did not answer in time.")

## The authoritative WebSocket room changed while ENet owned the body.
func _on_room_changed(room: String) -> void:
	if _phase == "admitted" and room != MovementAuthority.ROOM_CAMPUS:
		_fail("Left the campus for room '%s'." % room)

func _fail(reason: String) -> void:
	if _fell_back:
		return
	_phase = "rejected"
	push_warning("[EnetGameplay] " + reason)
	_recover(reason)

## Deliberately stay on the standard connection, without ever trying ENet.
func _use_legacy(reason: String) -> void:
	_phase = "legacy"
	print("[EnetGameplay] standard connection: %s" % reason)
	_recover(reason)

## Hand movement, collision and membership back to the pre-ENet game.
##
## Everything here is idempotent and gated on ``_fell_back``, because it is
## reached from a rejected admission, an expired deadline, a room change and a
## visiting player at startup -- and any two of those can arrive together.
func _recover(reason: String) -> void:
	if _fell_back:
		return
	_fell_back = true
	if movement != null:
		movement.stop()
	if client != null:
		# Auth callbacks must finish before their peer is closed.
		client.call_deferred("disconnect_from_server")
	if APIClient.realtime.room_changed.is_connected(_on_room_changed):
		APIClient.realtime.room_changed.disconnect(_on_room_changed)
	_restore_body()
	_restore_tiles()
	APIClient.realtime.external_movement = false
	(multiplayer as SceneMultiplayer).root_path = _previous_root
	_enable_legacy_remotes()
	if _status != null:
		_status.text = "Standard connection: " + reason

## Put the local body back exactly as the game's own controller left it.
func _restore_body() -> void:
	if not _body_prepared or _player_body == null or not is_instance_valid(_player_body):
		return
	_player_body.velocity = Vector2.ZERO
	_player_body.motion_mode = _saved_body_motion
	_player_body.collision_layer = _saved_body_layer
	_player_body.collision_mask = _saved_body_mask
	# Re-arm the character's own controller; the bridge is the only thing that
	# switched it off, so the bridge is the only thing that may switch it back.
	_player_body.set_physics_process(true)


func _restore_tiles() -> void:
	for tile in _saved_tiles:
		if is_instance_valid(tile):
			tile.collision_enabled = _saved_tiles[tile]
	_saved_tiles.clear()


func _enable_legacy_remotes() -> void:
	var world := get_parent()
	if world == null:
		return
	var remotes := world.get_node_or_null("RemotePlayers")
	if remotes != null and remotes.has_method("activate"):
		remotes.activate()

func _exit_tree() -> void:
	APIClient.realtime.external_movement = false
	# MultiplayerClient closes its peer in its own _exit_tree.
	if movement != null:
		movement.stop()
	(multiplayer as SceneMultiplayer).root_path = _previous_root

func phase() -> String:
	return _phase

func is_multiplayer_active() -> bool:
	return active and _phase == "admitted"
