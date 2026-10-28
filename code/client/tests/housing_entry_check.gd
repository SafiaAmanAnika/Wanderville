extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	print("HOUSING_CHECK ", label, " ", "PASS" if ok else "FAIL")
	if not ok: failures += 1

func run() -> void:
	root.size = Vector2i(1200, 800)
	var session := root.get_node("Global")
	session.clear_session()
	session.selected_character = "girl_a"
	root.get_node("APIClient").base_url = "http://127.0.0.1:1"
	var world: Node2D = load("res://Scenes/world.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	await create_timer(1.0).timeout
	var state := root.get_node("GameState")
	var house_id := int(OS.get_environment("HOUSING_ID"))
	if house_id < 1: house_id = 1
	state.house = {"id": house_id, "position": Vector2(1200, 1200), "stage": "done", "floor": "honey", "furniture": []}
	var housing: Node
	for child in world.get_children():
		if child.get_script() == load("res://Scripts/housing/house_manager.gd"):
			housing = child
	check(housing != null, "manager_present")
	housing._spawn_exterior()
	await housing._enter_house()
	await create_timer(1.0).timeout
	var player := get_first_node_in_group("player") as Node2D
	check(housing.inside, "entered_interior")
	check(player.global_position.distance_to(housing.interior.spawn_position()) < 100, "player_stays_at_interior_spawn")
	check(housing.interior.get_node("honey").visible, "chosen_floor_visible")
	var camera := root.get_camera_2d()
	check(camera.limit_right > 60000, "interior_camera_follows_outside_campus")
	check(camera.zoom.is_equal_approx(Vector2(0.3, 0.3)), "interior_keeps_original_zoom")
	print("HOUSING_POSITION player=", player.global_position, " camera=", root.get_camera_2d().get_screen_center_position())
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("HOUSING_CAPTURE"))
	await housing._leave_house()
	check(not housing.inside, "exit_restores_outdoors")
	check(camera.limit_right < 5000, "camera_restores_campus_bounds")
	print("HOUSING_RESULT failures=", failures)
	quit(failures)
