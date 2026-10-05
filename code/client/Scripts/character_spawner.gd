extends Node2D
# Attached to the World scene. Swaps the default "girl" player for the character
# chosen on the select screen (charagirlA, charaboyB, ...).

const CHARA_SCALE := Vector2(1.18, 1.18)   # chara sheets are 448px; this matches the old girl's size


func _ready() -> void:
	spawn_selected_character()


func spawn_selected_character() -> void:
	var path: String = Global.CHARACTER_SCENES.get(Global.selected_character, "")
	if path == "" or path.ends_with("player1.tscn"):
		return   # nothing chosen (or the original girl) -> keep the girl already in the world

	var old := get_node_or_null("girl") as Node2D
	if old == null:
		return
	var player := (load(path) as PackedScene).instantiate() as Node2D
	player.position = old.position
	player.scale = CHARA_SCALE

	# move the camera from the old girl to the new character
	var camera := old.get_node_or_null("Camera2D")
	if camera:
		old.remove_child(camera)
		camera.position = Vector2.ZERO
		player.add_child(camera)

	# remove the old girl, then give the new one the same name and place in the tree
	var index := old.get_index()
	old.remove_from_group("player")
	old.name = "girl_old"
	old.queue_free()
	player.name = "girl"
	add_child(player)
	move_child(player, index)
