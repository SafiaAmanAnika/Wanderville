extends SceneTree
var lobby: Node2D
var player: CharacterBody2D
var interactions: Node
var api: Node
var session: Node
var state: Node
var failures := 0
var output := ""

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	print("INTERACTION_CHECK ", label, " ", "PASS" if ok else "FAIL")
	if not ok:
		failures += 1

func wait_for(predicate: Callable, seconds := 15.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < end:
		if predicate.call():
			return true
		await create_timer(0.05).timeout
	return false

func press(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func approach(position: Vector2) -> void:
	player.position = position
	player.velocity = Vector2.ZERO
	await physics_frame
	await physics_frame
	await create_timer(0.12).timeout

func screenshot(name: String) -> void:
	if DisplayServer.get_name() == "headless" or output.is_empty():
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))

func run() -> void:
	output = OS.get_environment("TEST_LOBBY_OUTPUT")
	api = root.get_node("APIClient")
	session = root.get_node("Global")
	state = root.get_node("GameState")
	var online := OS.get_environment("TEST_LOBBY_ONLINE") == "1"
	if online:
		var login: Dictionary = await api.login("lobby_player", "Strong-Pass123!")
		check(login.get("ok",false), "real_backend_login")
		if failures:
			quit(1)
			return
		var data: Dictionary = api.data_of(login)
		session.set_session(data.access_token, data.player, data.refresh_token)
		check(await state.load_from_backend(), "real_game_state_loaded")
	lobby = load("res://Scenes/SocialLobby.tscn").instantiate()
	root.add_child(lobby)
	current_scene = lobby
	player = lobby.get_node("LobbyPlayer")
	interactions = lobby.get_node("LobbyInteractions")
	await physics_frame
	await physics_frame
	await process_frame
	check(player.position == Vector2(960,544) and player.scale == Vector2(0.75,0.75), "spawn_and_scale_preserved")
	check(lobby.get_node("Camera2D").zoom.is_equal_approx(Vector2(1.2,1.2)), "camera_preserved")
	check(lobby.get_node("StaticCollisions").get_child_count() == 24, "solid_collision_count_preserved")
	check(not interactions.prompt.visible and interactions.modal == "", "no_center_prompt_or_auto_open")
	check(lobby.get_node("Receptionist") is AnimatedSprite2D and lobby.get_node("Receptionist").get_script() == null, "npc_stationary_animated_sprite")
	check(lobby.get_node("Receptionist").sprite_frames.get_frame_texture("idle_front", 0).get_image().detect_alpha() != Image.ALPHA_NONE, "npc_transparent_asset")
	check(lobby.get_node("ReceptionCounterForeground").region_rect == Rect2(790,258,340,94), "desk_occludes_npc")
	await screenshot("room")
	# Test the real controller at 300 units/s, including authenticated local play.
	var start := player.position
	Input.action_press("ui_right")
	for i in 30:
		await physics_frame
	Input.action_release("ui_right")
	await physics_frame
	print("INTERACTION_SPEED distance=", player.position.distance_to(start), " ticks=", Engine.physics_ticks_per_second)
	check(absf(player.position.distance_to(start) - 30.0 * 300.0 / Engine.physics_ticks_per_second) < 11, "existing_speed_and_authenticated_local_walk")
	await approach(Vector2(960,365))
	check(interactions.prompt.visible and interactions.nearest != null and interactions.nearest.name == "Reception", "reception_proximity")
	await screenshot("reception-prompt")
	press(KEY_E)
	await process_frame
	check(interactions.modal == "reception" and interactions.dialogue.text == "Welcome to Wanderville! Looking for someone?", "E_opens_reception")
	press(KEY_E)
	check(interactions.modal == "reception", "repeat_E_no_duplicate")
	start = player.position
	Input.action_press("ui_right")
	for i in 12:
		await physics_frame
	Input.action_release("ui_right")
	check(player.position == start and not interactions.prompt.visible, "modal_locks_movement_and_prompt")
	await screenshot("dialogue")
	press(KEY_ESCAPE)
	await process_frame
	check(interactions.modal == "" and not state.menu_open and not state.social_open, "escape_closes_and_unlocks")
	Input.action_press("ui_right")
	for i in 10:
		await physics_frame
	Input.action_release("ui_right")
	await physics_frame
	check(player.position.x > start.x + 35, "movement_resumes")
	await approach(Vector2(960,600))
	check(not interactions.prompt.visible, "prompt_hides_out_of_range")
	# Overlapping detectors still select exactly the closest interactable.
	var friend_zone: Node2D = interactions.zones.get_node("FriendsBoard")
	var original := friend_zone.position
	friend_zone.position = Vector2(1040,420)
	await approach(Vector2(960,365))
	check(interactions.nearest != null and interactions.nearest.name == "Reception", "nearest_overlapping_zone")
	friend_zone.position = original
	if online:
		press(KEY_E)
		interactions.primary.pressed.emit()
		await process_frame
		var social: Node = interactions.social
		check(social.visible and social.view.selected == 2, "reception_opens_existing_search")
		check(social.status.text.contains("two username"), "short_query_state")
		social.get_node("%Search").text = "lobby_friend"
		social.get_node("%Find").pressed.emit()
		check(social.status.text == "Loading...", "search_loading_state")
		check(await wait_for(func(): return not social._loading), "search_finished")
		check(social._rows.size() == 1 and social._rows[0].username == "lobby_friend", "real_search_result")
		check(social._rows[0].get("character_code", "") == "boy_a", "real_profile_character_in_search")
		check(social._cards.get_child_count() == 1, "real_result_has_visual_card")
		social._cards.get_child(0).pressed.emit()
		check(social._profile_name.text == "lobby_friend", "card_selects_real_profile")
		check(social._profile_picture.get_child(social._profile_picture.get_child_count() - 1) is Node2D, "profile_renders_actual_character")
		await screenshot("search-results")
		check(not social.get_node("%Primary").disabled and social.get_node("%Primary").text == "Add friend", "existing_search_action")
		social._cards.get_child(0).get_node("Row/PrimaryAction").pressed.emit()
		check(await wait_for(func(): return not social._acting and not social._loading), "real_friend_request_sent")
		check(social.status.text == "Updated.", "friend_request_success")
		social.get_node("%Search").text = "no_match_xyz123"
		social.get_node("%Find").pressed.emit()
		await wait_for(func(): return not social._loading)
		check(social._rows.is_empty() and social.status.text == "No players here yet.", "search_empty_state")
		var base: String = api.base_url
		api.base_url = "http://127.0.0.1:1"
		social.get_node("%Find").pressed.emit()
		await wait_for(func(): return not social._loading)
		check(social.status.text != "Loading..." and social.status.text != "No players here yet.", "search_network_error_state")
		api.base_url = base
		press(KEY_ESCAPE)
		await process_frame
		check(not state.menu_open and not state.social_open, "escape_from_focused_search")
		await approach(Vector2(1670,380))
		check(interactions.nearest != null and interactions.nearest.name == "RequestsBoard", "requests_prompt")
		press(KEY_E)
		await wait_for(func(): return not social._loading)
		check(social.view.selected == 1 and social._rows.size() == 2, "real_request_list_incoming_and_sent")
		var incoming := -1
		for i in social._rows.size():
			if social._rows[i].username == "lobby_request": incoming = i
		check(incoming >= 0, "seeded_real_incoming_request")
		if incoming >= 0:
			social.people.select(incoming)
			social.people.item_selected.emit(incoming)
			social.get_node("%Primary").pressed.emit()
			await wait_for(func(): return not social._acting and not social._loading)
			check(social.status.text == "Updated.", "accept_real_request")
		press(KEY_ESCAPE)
		await approach(Vector2(250,380))
		check(interactions.nearest != null and interactions.nearest.name == "FriendsBoard", "friends_prompt")
		press(KEY_E)
		await wait_for(func(): return not social._loading)
		check(social.view.selected == 0 and social._rows.size() == 1 and social._rows[0].username == "lobby_request", "real_friend_list")
		check(not social.get_node("%SearchRow").visible, "friends_hide_reception_query")
		social._cards.get_child(0).pressed.emit()
		await screenshot("friends")
		press(KEY_ESCAPE)
	else:
		for position in [Vector2(250,380),Vector2(1670,380)]:
			await approach(position)
			press(KEY_E)
			check(interactions.heading.text == "Sign in required", "offline_social_signin_state")
			press(KEY_ESCAPE)
	# No invented destination at either side arch.
	await approach(Vector2(484,270))
	check(interactions.nearest == null, "side_arch_has_no_placeholder_action")
	await approach(Vector2(960,930))
	check(interactions.nearest != null and interactions.nearest.name == "Entrance", "leave_prompt")
	press(KEY_E)
	check(interactions.modal == "leave", "leave_confirmation")
	press(KEY_ESCAPE)
	check(current_scene == lobby, "leave_cancel_stays_in_lobby")
	if online:
		var token: String = session.token
		var version: int = session.session_version
		var world_id: int = state.current_world_id()
		# Preload the unchanged campus while suppressing its known TileSet art flood.
		Engine.print_error_messages = false
		var packed: PackedScene = load("res://Scenes/world.tscn")
		Engine.print_error_messages = true
		check(packed != null, "normal_world_resource_loads")
		press(KEY_E)
		interactions.primary.pressed.emit()
		check(await wait_for(func(): return current_scene != null and current_scene.scene_file_path == "res://Scenes/world.tscn",30.0), "leave_uses_real_world_transition")
		check(await wait_for(func(): return not root.get_node("SceneManager")._is_transitioning), "transition_completes")
		check(session.token == token and session.session_version == version and state.current_world_id() == world_id, "auth_and_world_context_preserved")
		check(not state.menu_open and not state.social_open, "world_has_no_lobby_input_lock")
		check(await wait_for(func(): return api.realtime.connected), "normal_world_transport_reconnects")
	print("INTERACTION_RESULT failures=", failures)
	quit(1 if failures else 0)
