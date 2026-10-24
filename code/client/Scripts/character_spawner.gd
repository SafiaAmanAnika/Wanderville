extends Node2D
# Attached to the World scene. Swaps the default "girl" player for the character
# chosen on the select screen (charagirlA, charaboyB, ...).

const CampusLayout := preload("res://Scripts/network/CampusLayout.gd")

const CHARA_SCALE := preload("res://Scripts/chara_frames.gd").GAMEPLAY_SCALE
var _movement_keys: Array[Dictionary] = []


func _enter_tree() -> void:
	for binding in [["ui_up",KEY_W],["ui_left",KEY_A],["ui_down",KEY_S],["ui_right",KEY_D]]:
		var key := InputEventKey.new(); key.physical_keycode=binding[1]
		if not InputMap.action_has_event(binding[0],key):
			InputMap.action_add_event(binding[0],key)
			_movement_keys.append({"action":binding[0],"event":key})


func _exit_tree() -> void:
	for binding in _movement_keys:
		InputMap.action_erase_event(binding.action,binding.event)
		Input.action_release(binding.action)


func _ready() -> void:
	add_child(load("res://Scripts/inventory/storage_house.gd").new())   # click the CDS building -> storage menu
	add_child(load("res://Scripts/marketplace/cafe_entrance.gd").new()) #ehehe <333
	add_child(load("res://Scripts/social/lobby_entrance.gd").new())   # audi -> social; library -> customization
	spawn_selected_character()
	var player := get_node("girl") as Node2D
	SceneManager.restore_customization_return(player)
	if not CampusLayout.walkable(player.global_position):
		player.global_position = CampusLayout.spawn()
	var pets := preload("res://Scripts/pets/pet_manager.gd").new()
	pets.name = "Pets"
	add_child(pets)
	add_child(preload("res://Scripts/ui/onboarding_guide.gd").new())
	if OS.get_environment("GODOT_ENET_GAMEPLAY") == "1":
		var bridge := preload("res://Scripts/network/EnetGameplayBridge.gd").new()
		bridge.name = "EnetGameplayBridge"
		add_child(bridge)
		bridge.attach(get_node("girl"))


func spawn_selected_character() -> void:
	var path: String = Global.CHARACTER_SCENES.get(Global.selected_character, "")
	if path == "" or path.ends_with("player1.tscn"):
		return   # nothing chosen (or the original girl) -> keep the girl already in the world

	var old := get_node_or_null("girl") as Node2D
	if old == null:
		return
	var packed := Global.get_character_scene(Global.selected_character)
	if packed == null or packed.resource_path.ends_with("player1.tscn"):
		return # Leave the world's existing farmer intact when a replacement is unavailable.
	var player := packed.instantiate() as CharacterBody2D
	if player == null:
		return
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
