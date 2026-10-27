extends SceneTree
# Test driver only: loads the unmodified production world, with real login/state.
var world: Node
var bridge: Node
var api: Node
var session: Node
var state: Node
var failures := 0
var role := ""
var sync_dir := ""

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	print("GAMEPLAY_CHECK ", role, " ", label, " ", "PASS" if ok else "FAIL")
	if not ok:
		failures += 1

func wait_for(predicate: Callable, seconds := 30.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await create_timer(0.05).timeout
	return false

func mark(label: String) -> void:
	var file := FileAccess.open(sync_dir.path_join(role + "-" + label), FileAccess.WRITE)
	file.store_string("ready")

func _run() -> void:
	role = OS.get_environment("TEST_ROLE")
	sync_dir = OS.get_environment("TEST_SYNC_DIR")
	api = root.get_node("APIClient")
	session = root.get_node("Global")
	state = root.get_node("GameState")
	var response: Dictionary = await api.login("gameplay_" + role, "Strong-Pass123!")
	check(bool(response.get("ok", false)), "login")
	if failures:
		quit(1)
		return
	var data: Dictionary = api.data_of(response)
	session.set_session(data["access_token"], data["player"], data["refresh_token"])
	var character := "farmer_female" if role == "alpha" else "girl_a"
	var selected: Dictionary = await api.authenticated(HTTPClient.METHOD_PUT, "/profile", {"character_code": character, "map_code": "campus"})
	check(bool(selected.get("ok", false)), "select_character")
	check(await state.load_from_backend(), "hydrate_gameplay_state")
	if failures:
		quit(1)
		return
	# Resource loading emits the known TileSet art errors thousands of times.
	# Keep runtime/script errors enabled while instantiating and running.
	Engine.print_error_messages = false
	var packed := load("res://Scenes/world.tscn") as PackedScene
	Engine.print_error_messages = true
	world = packed.instantiate()
	root.add_child(world)
	current_scene = world
	DisplayServer.window_set_title("Wanderville normal game - " + role)
	bridge = world.get_node_or_null("EnetGameplayBridge")
	if OS.get_environment("TEST_LEGACY") == "1":
		check(bridge == null and not api.realtime.external_movement, "legacy_default")
		check(await wait_for(func(): return api.realtime.connected), "legacy_connected")
		var body: Node2D = world.get_node("girl")
		var start := body.global_position
		Input.action_press("ui_right")
		await create_timer(0.5).timeout
		Input.action_release("ui_right")
		check(body.global_position.distance_to(start) > 25, "legacy_moves")
		finish()
		return
	if state.current_world_id() > 0:
		await verify_private_farm()
		finish()
		return
	if OS.get_environment("TEST_BAD_VERSION") == "1":
		bridge.set("_version", "incompatible-test-map")
		check(await wait_for(func(): return bridge.phase() == "rejected"), "mismatch_rejected")
		check(bridge.movement.inputs_sent() == 0, "mismatch_no_inputs")
		finish()
		return
	check(await wait_for(func(): return bridge.phase() == "admitted" and api.realtime.connected), "enet_and_websocket_connected")
	check(await wait_for(func(): return bridge.movement.remote_ids().size() == 1, 60.0), "one_remote")
	check(get_nodes_in_group("player").size() == 1, "one_local_player")
	check(world.get_node("RemotePlayers").avatars.is_empty(), "no_websocket_duplicates")
	check(world.get_node("girl/Camera2D") == root.get_viewport().get_camera_2d(), "original_camera")
	check(world.has_node("WorldHUD") and world.has_node("FarmController") and world.has_node("Map"), "production_world_nodes")
	check(bridge.movement._uses_scene_collision and not world.has_node("CampusCollision"), "reuse_live_map_collision")
	if OS.get_environment("TEST_MANUAL_SECONDS") != "":
		print("GAMEPLAY_MANUAL_READY ", role)
		await create_timer(float(OS.get_environment("TEST_MANUAL_SECONDS"))).timeout
		finish()
		return
	var body: Node2D = world.get_node("girl")
	await wait_for(func(): return bridge.movement.snapshot_count() > 10)
	var start := body.global_position
	var remote: Node = bridge.movement.remote_avatar(bridge.movement.remote_ids()[0])
	var remote_start: Vector2 = remote.get("_body").global_position
	mark("ready")
	check(await wait_for(func(): return FileAccess.file_exists(sync_dir.path_join("alpha-ready")) and FileAccess.file_exists(sync_dir.path_join("beta-ready"))), "pair_ready")
	Input.action_press("ui_right")
	await create_timer(1.5).timeout
	var sprite := body.get_node("girl") if role == "alpha" else body.get_node("AnimatedSprite2D")
	var locomotion := "run" if role == "alpha" else "walk"
	var expected_fps := 10.0 if role == "alpha" else float(preload("res://Scripts/chara_frames.gd").FPS["walk"])
	check(sprite.is_playing() and str(sprite.animation).begins_with(locomotion), "locomotion_animation")
	check(sprite.speed_scale == 1.0 and sprite.sprite_frames.get_animation_speed(sprite.animation) == expected_fps, "locomotion_frame_rate")
	Input.action_release("ui_right")
	await create_timer(1.0).timeout
	check(body.global_position.distance_to(start) > 150, "normal_controller_moves")
	check(remote.get("_body").global_position.distance_to(remote_start) > 150, "remote_moves_on_campus")
	check(remote.get("_body").scale == (preload("res://Scripts/chara_frames.gd").GAMEPLAY_SCALE if role == "alpha" else Vector2(20, 20)), "remote_character_scale")
	check(body.global_position.distance_to(bridge.movement.authoritative_position()) < 60, "server_position_agrees")
	# Force local divergence while input is in flight: the server must win.
	body.global_position += Vector2(700, 0)
	check(await wait_for(func(): return body.global_position.distance_to(bridge.movement.authoritative_position()) < 30, 5.0), "authority_corrects_divergence")
	await create_timer(0.3).timeout
	var stopped := body.global_position
	state.menu_open = true
	Input.action_press("ui_right")
	await create_timer(0.7).timeout
	Input.action_release("ui_right")
	state.menu_open = false
	check(body.global_position.distance_to(stopped) < 20, "menu_blocks_movement")
	# Exercise a delayed legacy correction while ENet owns the body.
	var before := body.global_position
	api.realtime._correct_position = true
	api.realtime._handle_packet({"type": "snapshot", "data": {"players": [{"player_id": session.player_id, "sequence": 0, "x": 0, "y": 0}]}})
	check(body.global_position == before, "legacy_correction_ignored")
	check(api.realtime._last_sent_position == Vector2(INF, INF), "no_websocket_moves")
	mark("walked")
	await wait_for(func(): return FileAccess.file_exists(sync_dir.path_join("alpha-walked")) and FileAccess.file_exists(sync_dir.path_join("beta-walked")))
	if role == "beta":
		bridge.reconnect()
		check(await wait_for(func(): return bridge.phase() == "admitted"), "reconnected")
		check(await wait_for(func(): return bridge.movement.remote_ids().size() == 1), "remote_after_reconnect")
		mark("reconnected")
	else:
		check(await wait_for(func(): return bridge.movement.remote_ids().is_empty()), "remote_disappears")
		check(await wait_for(func(): return FileAccess.file_exists(sync_dir.path_join("beta-reconnected"))), "peer_reconnected")
		check(await wait_for(func(): return bridge.movement.remote_ids().size() == 1), "remote_returns_once")
	await create_timer(1.0).timeout
	check(get_nodes_in_group("player").size() == 1, "one_local_after_reconnect")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		check(picture.save_png(sync_dir.path_join(role + ".png")) == OK, "rendered_screenshot")
	mark("done")
	await wait_for(func(): return FileAccess.file_exists(sync_dir.path_join("alpha-done")) and FileAccess.file_exists(sync_dir.path_join("beta-done")))
	finish()

func finish() -> void:
	print("GAMEPLAY_RESULT ", JSON.stringify({"role": role, "failures": failures, "scene": current_scene.scene_file_path, "player_id": session.player_id, "display": DisplayServer.get_name()}))
	quit(1 if failures else 0)

func verify_private_farm() -> void:
	var state := root.get_node("GameState")
	var api := root.get_node("APIClient")
	var session := root.get_node("Global")
	var expected_room := "world:%d" % state.current_world_id()
	check(await wait_for(func(): return api.realtime.connected and api.realtime._room == expected_room), "private_farm_connected")
	check(bridge.phase() == "legacy" and not api.realtime.external_movement, "private_farm_uses_isolated_transport")
	check(bridge.movement == null, "private_farm_skips_campus_admission")
	var snapshot: Dictionary = await api.authenticated(HTTPClient.METHOD_GET, "/realtime/snapshot")
	var players: Array = api.data_of(snapshot).get("players", [])
	check(players.size() == 1 and int(players[0].player_id) == session.player_id, "owners_do_not_share_private_farms")
	check(get_nodes_in_group("player").size() == 1, "one_private_farm_player")
	var body: Node2D = world.get_node("girl")
	var start := body.global_position
	Input.action_press("ui_right")
	await create_timer(1.5).timeout
	var sprite := body.get_node("girl") if role == "alpha" else body.get_node("AnimatedSprite2D")
	var locomotion := "run" if role == "alpha" else "walk"
	check(sprite.is_playing() and str(sprite.animation).begins_with(locomotion), "private_farm_character_animates")
	Input.action_release("ui_right")
	check(body.global_position.distance_to(start) > 25, "private_farm_character_moves")
	var stopped := body.global_position
	state.menu_open = true
	Input.action_press("ui_right")
	await create_timer(0.4).timeout
	Input.action_release("ui_right")
	state.menu_open = false
	check(body.global_position.distance_to(stopped) < 5, "private_farm_menu_blocks_movement")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(sync_dir.path_join(role + ".png")) == OK, "rendered_private_farm")
