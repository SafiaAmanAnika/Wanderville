extends SceneTree

var failures := 0

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	print("FARM_AUTH_CHECK ", message, " PASS" if value else " FAIL")
	if not value: failures += 1

func wait_for(predicate: Callable) -> bool:
	var end := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < end:
		if predicate.call(): return true
		await create_timer(0.05).timeout
	return false

func run() -> void:
	var account: Dictionary = JSON.parse_string(OS.get_environment("TEST_FARM_ACCOUNT"))
	var session := root.get_node("Global")
	var state := root.get_node("GameState")
	var api := root.get_node("APIClient")
	var manager := root.get_node("SceneManager")
	session.clear_session()
	session.set_session(account.token, {"id":account.player_id,"username":account.username})
	var response: Dictionary = await api.update_profile({"character_code":"girl_a","map_code":"campus"})
	check(response.get("ok",false), "account setup saves")
	check(await state.load_from_backend(), "real account state loads")
	manager.goto_world()
	check(await wait_for(func(): return current_scene != null and current_scene.scene_file_path == manager.WORLD_SCENE and not manager._is_transitioning), "normal world route finishes")
	var world := current_scene
	var farm: Node = world.get_node("FarmController")
	var player: CharacterBody2D = world.get_node("girl")
	player.set_physics_process(false)
	player.global_position = farm._tile_to_world(Vector2i(8,10))
	var camera: Camera2D = player.get_node("Camera2D")
	camera.position_smoothing_enabled = false
	camera.reset_smoothing()
	await create_timer(4).timeout
	check(farm._player_in_zone and not farm._blocked(), "signed-in player can farm after entering the zone")
	var click := InputEventMouseButton.new()
	click.position = root.get_canvas_transform() * farm._tile_to_world(Vector2i(9,10))
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	root.push_input(click, true)
	check(await wait_for(func(): return farm.tilled_tiles.has("9,10")), "rendered viewport click sends a real till request")
	await process_frame
	check(farm._cursor.visible and farm._hover_tile() == Vector2i(9,10), "signed-in tile outline follows the same mouse coordinates")
	response = await api.authenticated(HTTPClient.METHOD_GET,"/farm/plots")
	var plots: Array = api.data_of(response).get("plots",[])
	check(plots.any(func(plot: Dictionary): return int(plot.x)==9 and int(plot.y)==10 and plot.is_tilled), "clicked soil is persisted by the server")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("TEST_FARM_OUTPUT").path_join("signed-in-till.png"))
	print("FARM_AUTH_RESULT failures=",failures)
	quit(1 if failures else 0)
