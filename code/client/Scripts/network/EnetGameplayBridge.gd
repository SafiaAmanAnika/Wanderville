extends Node
class_name EnetGameplayBridge
## Opt-in normal-world movement. WebSocket still carries gameplay services.
## The dedicated server must also use GODOT_ENET_GAMEPLAY=1.

var movement: MovementClient
var client: MultiplayerClient
var link: NetworkLink
var active := false
var _player_body: CharacterBody2D
var _phase := "off"
var _version := ""
var _retry_at := 0
var _handshake_deadline := 0
var _previous_root: NodePath
var _status: Label

func attach(body: CharacterBody2D) -> void:
	if active or body == null:
		return
	_previous_root = (multiplayer as SceneMultiplayer).root_path
	active = true
	_player_body = body
	body.set_physics_process(false)
	body.velocity = Vector2.ZERO
	APIClient.realtime.external_movement = true
	var world := get_parent()
	var map := world.get_node("Map") as Node2D
	_version = CampusCollision.live_version(map)
	if map.position != CampusCollision.WORLD_OFFSET or map.scale != Vector2.ONE or map.rotation != 0.0:
		_fail("Campus transform does not match the dedicated server.")
		return
	# Shared geometry currently includes static polygons, not TileSet physics.
	# Disable only tile collision on these runtime instances in ENet mode.
	for tile in map.find_children("*", "TileMapLayer", true, false):
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
	body.collision_layer = MovementAuthority.LAYER_PLAYER
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

func reconnect() -> void:
	if movement == null:
		return
	_on_disconnected()

func _process(_delta: float) -> void:
	if _phase == "reconnecting" and Time.get_ticks_msec() >= _retry_at:
		_connect()
	elif _phase == "checking campus" and Time.get_ticks_msec() > _handshake_deadline:
		_fail("The server did not provide a campus version.")

func _fail(reason: String) -> void:
	_phase = "rejected"
	if is_instance_valid(movement):
		movement.stop()
	if client != null:
		# Auth callbacks must finish before closing their peer.
		client.call_deferred("disconnect_from_server")
	if _status != null:
		_status.text = "Experimental ENet: " + reason
	push_warning("[EnetGameplay] " + reason)

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
