extends Node2D

# Presentation only: reuse the actual character scene and animation helper.
var avatars: Dictionary = {}
var targets: Dictionary = {}
var _active := false


func _ready() -> void:
	# ENet owns remote avatars while it is connected. The legacy snapshot stream
	# is only connected here when ENet is not in use, or later by the bridge if
	# ENet falls back to the standard connection.
	if OS.get_environment("GODOT_ENET_GAMEPLAY") == "1":
		return
	activate()


## Connect the WebSocket snapshot stream. Safe to call more than once.
func activate() -> void:
	if _active:
		return
	_active = true
	if not APIClient.realtime.snapshot_received.is_connected(_snapshot):
		APIClient.realtime.snapshot_received.connect(_snapshot)
	if not APIClient.realtime.connection_changed.is_connected(_connection):
		APIClient.realtime.connection_changed.connect(_connection)


func _connection(connected: bool) -> void:
	if not connected:
		if avatars.is_empty():
			return
		_snapshot({"players": []})


func _snapshot(snapshot: Dictionary) -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	var visible_ids: Dictionary = {}
	var local := tree.get_first_node_in_group("player") as Node2D
	if local == null:
		return
	for entry in snapshot.get("players", []):
		var id := int(entry.get("player_id", 0))
		if id == Global.player_id:
			continue
		visible_ids[id] = true
		var target := Vector2(float(entry["x"]), float(entry["y"]))
		if not avatars.has(id):
			var actor := Global.get_character_scene("player1").instantiate() as CharacterBody2D
			actor.name = "Remote_%d" % id
			actor.use_saved_appearance = false
			actor.remove_from_group("player")
			actor.process_mode = Node.PROCESS_MODE_DISABLED
			actor.collision_layer = 0
			actor.collision_mask = 0
			actor.scale = local.scale
			for camera in actor.find_children("*", "Camera2D", true, false):
				camera.enabled = false
			for audio in actor.find_children("*", "AudioStreamPlayer2D", true, false):
				audio.autoplay = false
			preload("res://Scripts/ui/player_namecard.gd").attach(actor, str(entry.get("username", "Player")))
			add_child(actor)
			actor.remove_from_group("player") # _ready adds the controller to this group.
			actor.global_position = target
			# Sprite animation is the only remote child allowed to process.
			actor.get_node("girl").process_mode = Node.PROCESS_MODE_ALWAYS
			avatars[id] = actor
		targets[id] = target
	for id in avatars.keys():
		if not visible_ids.has(id):
			avatars[id].queue_free()
			avatars.erase(id)
			targets.erase(id)


func _process(delta: float) -> void:
	for id in avatars:
		var actor: CharacterBody2D = avatars[id]
		var offset: Vector2 = targets[id] - actor.global_position
		actor._update_animation(offset.normalized() if offset.length() > 2.0 else Vector2.ZERO)
		if offset.length() > 1500.0:
			actor.global_position = targets[id]
		else:
			actor.global_position = actor.global_position.lerp(targets[id], 1.0 - exp(-12.0 * delta))
