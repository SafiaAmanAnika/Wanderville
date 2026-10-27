extends Node2D
## Shared lobby player spawner. Movement and animation stay in the character script;
## this only spawns the currently selected character and keeps the camera inside.

# Rooms use their own art proportions; match the existing 0.72 receptionist.
const PLAYER_SCALE := Vector2(0.72, 0.72)
signal player_spawned(body: CharacterBody2D)

@onready var camera: Camera2D = $Camera2D
var player: CharacterBody2D
var _added_keys: Array[Dictionary] = []
var _preferred_zoom := 1.2


func _enter_tree() -> void:
	# The player must exist before the interaction zones resolve their player,
	# and children enter the tree before this node's own _ready runs.
	_add_wasd()
	if player == null or not is_instance_valid(player):
		player = _spawn_player()


func _ready() -> void:
	_add_camera_follow()
	_preferred_zoom = camera.zoom.x
	get_viewport().size_changed.connect(_fit_camera)
	_fit_camera()
	if player != null:
		camera.global_position = player.global_position
	camera.reset_smoothing()
	camera.force_update_scroll()
	player_spawned.emit(player)


func respawn_player() -> CharacterBody2D:
	# Swap in a different character while keeping the spot they were standing on.
	if player == null or not is_instance_valid(player):
		player = _spawn_player()
		_add_camera_follow()
		player_spawned.emit(player)
		return player
	var spot := player.global_position
	remove_child(player)
	player.queue_free()
	player = _spawn_player()
	if player != null:
		player.global_position = spot
		_add_camera_follow()
	player_spawned.emit(player)
	return player


func _add_camera_follow() -> void:
	if player == null or player.has_node("CameraFollow"):
		return
	var follow := RemoteTransform2D.new()
	follow.name = "CameraFollow"
	follow.remote_path = camera.get_path()
	follow.update_rotation = false
	follow.update_scale = false
	player.add_child(follow)


func _spawn_player() -> CharacterBody2D:
	var packed := Global.get_character_scene(Global.selected_character)
	if packed == null:
		return null
	var body := packed.instantiate() as CharacterBody2D
	if body == null:
		return null
	body.name = "LobbyPlayer"
	body.scale = PLAYER_SCALE
	# Lobby movement is local for both existing character controllers.
	if "require_world_connection" in body:
		body.require_world_connection = false   # local room, no campus presence
	add_child(body)
	body.global_position = $PlayerSpawn.global_position
	if "facing" in body:
		body.facing = "back"
	var anim: AnimatedSprite2D = body.get("anim")
	if anim != null and anim.sprite_frames != null and anim.sprite_frames.has_animation("idle_back"):
		anim.play("idle_back")
	return body


func _fit_camera() -> void:
	# A very wide/tall window must not reveal space outside the room.
	var viewport_size := get_viewport_rect().size
	var room_size := Vector2(camera.limit_right - camera.limit_left,
			camera.limit_bottom - camera.limit_top)
	var fit := maxf(viewport_size.x / room_size.x, viewport_size.y / room_size.y)
	camera.zoom = Vector2.ONE * maxf(_preferred_zoom, fit)


func _add_wasd() -> void:
	for binding in [["ui_up", KEY_W], ["ui_left", KEY_A],
			["ui_down", KEY_S], ["ui_right", KEY_D]]:
		var event := InputEventKey.new()
		event.physical_keycode = binding[1]
		if not InputMap.action_has_event(binding[0], event):
			InputMap.action_add_event(binding[0], event)
			_added_keys.append({"action": binding[0], "event": event})


func _exit_tree() -> void:
	# Keep these extra bindings local to the room; preserve pre-existing ones.
	for binding in _added_keys:
		InputMap.action_erase_event(binding.action, binding.event)
		Input.action_release(binding.action)
