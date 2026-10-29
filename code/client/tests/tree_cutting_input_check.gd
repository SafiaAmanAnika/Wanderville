extends SceneTree


func _initialize() -> void:
	call_deferred("_check")


func _check() -> void:
	var world = load("res://Scenes/world.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	await process_frame
	await process_frame
	var trees = world.get_node("Map/Trees")
	trees.set_tree_season(0)
	var cutter = trees.get_node("TreeCutter")
	var tree := trees.get_node("Summer").get_child(0) as Node2D
	var player: Node2D = cutter._player()
	player.set_physics_process(false)
	player.global_position = cutter._trunk(tree) + Vector2(0, 80)
	await process_frame
	var key := InputEventKey.new()
	key.physical_keycode = KEY_C
	key.keycode = KEY_C
	key.pressed = true
	print("TREE_INPUT prompt=", cutter._prompt, " action=", key.is_action_pressed("cut_trees"))
	Input.parse_input_event(key)
	await process_frame
	await process_frame
	var failed := tree.visible
	print("TREE_INPUT cut=", not tree.visible, " busy=", cutter._busy)
	await create_timer(4.0).timeout
	quit(1 if failed else 0)
