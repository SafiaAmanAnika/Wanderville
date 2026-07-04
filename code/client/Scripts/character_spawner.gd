extends Node2D


func _ready() -> void:
	spawn_selected_character()


func spawn_selected_character() -> void:
	var existing := get_node_or_null("girl")
	var spawn_pos := Vector2(7377, -891)
	var spawn_scale := Vector2(20, 20)
	var camera: Node = null

	if existing:
		spawn_pos = existing.position
		spawn_scale = existing.scale
		camera = existing.get_node_or_null("Camera2D")
		if camera:
			existing.remove_child(camera)
		existing.queue_free()

	var scene: PackedScene = Global.get_character_scene(Global.selected_character)
	var player := scene.instantiate()
	player.name = "Player"
	player.position = spawn_pos
	player.scale = spawn_scale

	if camera:
		player.add_child(camera)
	else:
		_create_own_camera(player)

	add_child(player)


func _create_own_camera(player: Node2D) -> void:
	var cam := Camera2D.new()
	cam.name = "Camera2D"
	cam.position = Vector2(-10.15, -0.6)
	cam.zoom = Vector2(0.3, 0.3)
	player.add_child(cam)
