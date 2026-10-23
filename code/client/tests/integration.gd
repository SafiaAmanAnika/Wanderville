extends SceneTree

var api: Node
var session: Node
var state: Node
var world: Node
var ui: Node
var role := ""
var other := ""
var sync_dir := ""
var failures := 0
var probes: Array = []
var stale: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> bool:
	print("CHECK ", role, " ", label, " ", "PASS" if ok else "FAIL")
	if not ok:
		failures += 1
	return ok


func _wait(predicate: Callable, seconds: float = 15.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await create_timer(0.05).timeout
	return false


func _mark(label: String) -> void:
	var file := FileAccess.open(sync_dir.path_join(role + "_" + label), FileAccess.WRITE)
	file.store_string("ready")
	file.close()


func _select_first() -> bool:
	# Selecting into an empty list is a Godot error rather than a failed check,
	# and the reason the list is empty is the interesting part. Print it instead
	# of dying on the first empty load.
	if ui.people.get_item_count() == 0:
		print(
			"DIAG_EMPTY ", role,
			" view=", ui.view.selected,
			" rows=", ui._rows.size(),
			" loading=", ui._loading,
			" panel=", ui.panel.visible,
			" friends=", ui.friends.visible,
			" status=", ui.status.text
		)
		return false
	ui.people.select(0)
	return true


func _other_mark(label: String, seconds: float = 20.0) -> bool:
	return await _wait(func() -> bool: return FileAccess.file_exists(sync_dir.path_join(other + "_" + label)), seconds)


func _probe(path: String) -> void:
	probes.append(await api.authenticated(HTTPClient.METHOD_GET, path))


func _old_request() -> void:
	stale = await api.authenticated(HTTPClient.METHOD_GET, "/integration/delay")


func _run() -> void:
	role = OS.get_environment("WANDERVILLE_TEST_ROLE")
	other = "bob" if role == "alice" else "alice"
	sync_dir = OS.get_environment("WANDERVILLE_TEST_SYNC")
	if role not in ["alice", "bob"] or sync_dir.is_empty():
		quit(2)
		return
	api = root.get_node("APIClient")
	session = root.get_node("Global")
	state = root.get_node("GameState")
	var response: Dictionary = await api.login("integration_" + role, OS.get_environment("WANDERVILLE_TEST_PASSWORD"))
	if not _check(bool(response.get("ok", false)), "real_http_login"):
		quit(1)
		return
	var login: Dictionary = api.data_of(response)
	session.set_session(login["access_token"], login["player"], login["refresh_token"])
	_check(await state.load_from_backend(), "initial_saved_state")
	var version: int = session.session_version
	_old_request()
	await process_frame
	session.set_session(login["access_token"], login["player"], login["refresh_token"])
	await _wait(func() -> bool: return not stale.is_empty())
	_check(stale.get("stale", false) and session.session_version > version, "same_account_old_response_rejected")
	session.token = "expired-for-test"
	_probe("/profile")
	_probe("/inventory/")
	_probe("/economy/")
	await _wait(func() -> bool: return probes.size() == 3)
	_check(probes.size() == 3 and probes.all(func(item: Dictionary) -> bool: return bool(item.get("ok", false))), "concurrent_http_coordinated_refresh")
	_check(await state.load_from_backend(), "restored_after_refresh")
	# The existing map has invalid TileSet atlas entries. Avoid tens of thousands
	# of identical import diagnostics here; runtime errors remain enabled.
	Engine.print_error_messages = false
	var world_scene: PackedScene = load("res://Scenes/world.tscn")
	Engine.print_error_messages = true
	world = world_scene.instantiate()
	root.add_child(world)
	current_scene = world
	# Social lives in the Social Lobby now; drive the same shared panel directly
	# against the world's authenticated transport and backend.
	ui = load("res://Scenes/social_panel.tscn").instantiate()
	world.add_child(ui)
	_check(await _wait(func() -> bool: return api.realtime.connected), "websocket_authenticated")
	_mark("world")
	_check(await _other_mark("world", 120), "other_world_ready")
	var remotes: Node = world.get_node("RemotePlayers")
	_check(await _wait(func() -> bool: return remotes.avatars.size() == 1), "remote_avatar_rendered")
	if remotes.avatars.size() == 1:
		var actor: Node = remotes.avatars.values()[0]
		_check(not actor.is_in_group("player") and actor.process_mode == Node.PROCESS_MODE_DISABLED and actor.find_children("*", "Camera2D", true, false).is_empty(), "remote_input_camera_isolation")
	var player: Node2D = get_first_node_in_group("player")
	var start: Vector2 = player.global_position
	Input.action_press("ui_right")
	await create_timer(0.3).timeout
	Input.action_release("ui_right")
	_check(player.global_position.distance_to(start) > 10, "local_movement")
	await create_timer(0.5).timeout
	_check(api.realtime._sequence > 1, "movement_and_heartbeats")
	_mark("moved")
	await _other_mark("moved")
	if remotes.targets.size() == 1:
		_check(remotes.targets.values()[0].x > preload("res://Scripts/network/CampusLayout.gd").spawn().x + 8.0, "received_other_movement")
	ui._toggle(true)
	ui.message.text = "nearby " + role + " shit"
	await ui._send()
	_check(await _wait(func() -> bool: return ui._nearby.any(func(item: Dictionary) -> bool: return item["body"] == "nearby " + other + " ****")), "nearby_recipient_filtering")
	var nearby_count: int = ui._nearby.size()
	await create_timer(0.6).timeout
	_check(ui._nearby.size() == nearby_count and nearby_count == 2, "nearby_no_duplicates")
	ui._toggle(false)
	ui.view.select(2 if role == "alice" else 1)
	ui.get_node("Dock/Panel/Body/Friends/SearchRow/Search").text = "integration_bob"
	if role == "alice":
		await _wait(func() -> bool: return not ui._loading)
		await ui._load_people()
		_check(ui._rows.size() == 1, "friend_username_search")
		ui.people.select(0)
		await ui._act("request")
		_mark("requested")
		_check(await _other_mark("accepted"), "friend_request_accepted")
	else:
		await _other_mark("requested")
		await _wait(func() -> bool: return not ui._loading)
		await ui._load_people()
		_check(ui._rows.size() == 1, "incoming_request_list")
		ui.people.select(0)
		await ui._act("accept")
		_mark("accepted")
	ui.view.select(0)
	await _wait(func() -> bool: return not ui._loading)
	await ui._load_people()
	_check(ui._rows.size() == 1 and ui._rows[0].get("online", false), "friend_online_presence")
	ui.people.select(0)
	ui._primary()
	ui.message.text = "private " + role
	await ui._send()
	_check(await _wait(func() -> bool: return ui._private.get(ui._target, []).any(func(item: Dictionary) -> bool: return item["body"] == "private " + other)), "private_recipient_delivery_and_history")
	start = player.global_position
	var water: int = state.water_drops
	Input.action_press("ui_right")
	Input.action_press("interact")
	Input.action_press("collect_water")
	await create_timer(0.3).timeout
	Input.action_release("ui_right")
	Input.action_release("interact")
	Input.action_release("collect_water")
	_check(player.global_position == start and state.water_drops == water, "typing_blocks_gameplay_shortcuts")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(sync_dir.path_join(role + "_social.png"))
	_mark("social")
	await _other_mark("social")
	if role == "alice":
		api.realtime._schedule_reconnect()
		_check(await _wait(func() -> bool: return api.realtime.connected), "reconnect_restores_session")
		_check(ui._nearby.is_empty(), "reconnect_does_not_replay_previous_room_epoch")
		ui.set_open(false)
		await _farm()
		_mark("farm")
		await _other_mark("farm", 60)
		# Blocking deletes the friendship and unblocking does not bring it back,
		# so the invitation flow needs to run first while these two are still
		# friends; the block test runs last as the teardown it now is.
		await _visit(true)
		ui._toggle(false)
		await _wait(func() -> bool: return not ui._loading)
		await ui._load_people()
		ui.people.select(0)
		await ui._act("block")
		_mark("blocked")
		await _other_mark("blocked_checked")
		ui.view.select(3)
		await _wait(func() -> bool: return not ui._loading)
		await ui._load_people()
		ui.people.select(0)
		await ui._act("unblock")
		ui.set_open(false)
	else:
		await _other_mark("farm", 60)
		# Mark his own arrival too: alice waits on this second mark before she
		# starts inviting, so neither client enters the flow on its own.
		_mark("farm")
		await _visit(false)
		await _other_mark("blocked")
		response = await api.get_direct_messages(1)
		_check(int(response.get("status_code", 0)) == 403, "blocking_private_access_enforced")
		_check(await _wait(func() -> bool: return remotes.avatars.is_empty()), "blocked_remote_removed")
		_mark("blocked_checked")
	await api.logout()
	_check(not api.realtime.connected and api.realtime._watched_conversations.is_empty() and not session.is_logged_in(), "logout_socket_polling_cleanup")
	print("CLIENT_INTEGRATION_RESULT ", role, " failures=", failures)
	quit(0 if failures == 0 else 1)


func _farm() -> void:
	var farm: Node = world.get_node("FarmController")
	await farm._server_action("till", Vector2i(2, 2), "2,2")
	await farm._server_action("till", Vector2i(3, 2), "3,2")
	await farm._server_action("plant", Vector2i(2, 2), "2,2", "wheat")
	_check(farm.active_crops.has("2,2") and farm.get_node_or_null("CropVisual_2,2/AnimatedSprite2D") != null, "actual_crop_scene_planted")
	await farm._server_action("water", Vector2i(2, 2), "2,2")
	_check(farm.get_node("CropVisual_2,2/AnimatedSprite2D").frame == 1, "single_watering_visual_frame")
	await create_timer(5.2).timeout
	await state.refresh_gameplay()
	_check(farm.get_node("CropVisual_2,2/AnimatedSprite2D").frame >= 2, "inspector_growth_timing")
	farm._dragging = true
	farm._drag_key = "2,2"
	farm._drag_crop = farm.active_crops["2,2"].duplicate()
	await farm._relocate(Vector2i(3, 2))
	_check(not farm.active_crops.has("2,2") and farm.active_crops.has("3,2"), "crop_relocation_persisted")
	var previous_water: int = state.water_drops
	world.queue_free()
	await process_frame
	world = load("res://Scenes/world.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	ui = load("res://Scenes/social_panel.tscn").instantiate()
	world.add_child(ui)
	farm = world.get_node("FarmController")
	_check(farm.get_node_or_null("CropVisual_3,2/AnimatedSprite2D") != null, "saved_crop_scene_restored")
	await create_timer(13.0).timeout
	await state.refresh_gameplay()
	_check(farm.get_node("CropVisual_3,2/AnimatedSprite2D").frame == 4, "restored_crop_harvest_frame")
	if DisplayServer.get_name() != "headless":
		var player: Node2D = get_first_node_in_group("player")
		var camera: Camera2D = player.get_node("Camera2D")
		camera.global_position = farm._tile_to_world(Vector2i(3, 2))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(sync_dir.path_join("restored_crop.png"))
	await farm._server_action("harvest", Vector2i(3, 2), "3,2")
	_check(not farm.active_crops.has("3,2") and state.water_drops == previous_water, "harvest_authoritative_reward_no_extra_water")


# One player hosts, the other visits, and the whole invitation lifecycle runs
# through the panel: invite, accept, read-only standing, a voluntary leave, then
# a second visit that ends with the host ejecting the guest.
func _visit(is_host: bool) -> void:
	# Every sync mark in here is prefixed with "visit_": the friendship handshake
	# earlier in the run already wrote a bare "accepted", and a waiter that picks
	# up that stale file skips the step it was meant to sequence.
	ui._toggle(false)
	ui.view.select(0)
	await _wait(func() -> bool: return not ui._loading)
	await ui._load_people()
	_select_first()
	await ui._act("invite_farm")
	if not ui.status.text.begins_with("Invitation sent"):
		print("DIAG_INVITE role=", "host" if is_host else "guest", " status=", ui.status.text)
	_check(ui.status.text.begins_with("Invitation sent"), "farm_invitation_sent")
	if is_host:
		_mark("visit_invited")
		_check(await _other_mark("visit_accepted", 60), "guest_accepted_invitation")
		await ui._farm_visitors()
		if not (ui._people_kind == "visitor" and ui._rows.size() == 1):
			print("DIAG_VISITORS kind=", ui._people_kind, " rows=", ui._rows.size(), " status=", ui.status.text)
		_check(ui._people_kind == "visitor" and ui._rows.size() == 1, "host_lists_visitor")
		_mark("visit_arrived")
		_check(await _other_mark("visit_left", 60), "guest_left_voluntarily")
		await ui._farm_visitors()
		_check(ui._rows.is_empty(), "slot_released_after_leave")
		await ui._back_to_people()
		await _wait(func() -> bool: return not ui._loading)
		await ui._load_people()
		_select_first()
		await ui._act("invite_farm")
		_mark("visit_reinvited")
		_check(await _other_mark("visit_accepted_twice", 60), "reinvite_after_leave")
		_mark("visit_returned")
		await ui._farm_visitors()
		_select_first()
		await ui._remove_visitor()
		_check(ui._rows.is_empty(), "host_ejected_visitor")
		_mark("visit_kicked")
		_check(await _other_mark("visit_kicked_checked", 60), "guest_saw_the_kick")
	else:
		_check(await _other_mark("visit_invited", 60), "invitation_reached_guest")
		ui.view.select(ui.VIEW_INVITATIONS)
		await _wait(func() -> bool: return not ui._loading)
		await ui._load_people()
		_check(
			ui._rows.size() == 1 and str(ui._rows[0].get("host_username", "")) == "integration_alice",
			"invitation_inbox_names_host"
		)
		_select_first()
		await ui._invitation_action("accept")
		_mark("visit_accepted")
		_check(state.is_visiting() and state.read_only, "visit_session_is_read_only")
		_check(api.realtime._room == "world:%d" % state.current_world_id(), "visitor_stands_in_host_world")
		_check(await _other_mark("visit_arrived", 60), "host_confirmed_visitor")
		# The panel must refuse before spending a request, and the server must
		# refuse even when the client sends the write anyway.
		var farm: Node = world.get_node("FarmController")
		var before: int = state.farm_plots.size()
		await farm._server_action("till", Vector2i(7, 2), "7,2")
		_check(state.farm_plots.size() == before and not farm.tilled_tiles.has("7,2"), "visitor_ui_blocks_farm_writes")
		var forced: Dictionary = await api.till_tile(7, 2)
		_check(int(forced.get("status_code", 0)) == 403, "server_rejects_visitor_write")
		await ui._leave_farm()
		_mark("visit_left")
		_check(not state.read_only and not state.is_visiting(), "leave_restores_own_session")
		_check(await _wait(func() -> bool: return api.realtime._room == "campus"), "visitor_returned_to_campus")
		_check(await _other_mark("visit_reinvited", 60), "host_reinvited_guest")
		ui.view.select(ui.VIEW_INVITATIONS)
		await _wait(func() -> bool: return not ui._loading)
		await ui._load_people()
		_select_first()
		await ui._invitation_action("accept")
		_mark("visit_accepted_twice")
		var ended: Array = []
		api.realtime.visit_ended.connect(func(message: String) -> void: ended.append(message))
		_check(await _other_mark("visit_kicked", 60), "host_ejected_guest")
		_check(await _wait(func() -> bool: return not ended.is_empty(), 40), "kick_ends_visit")
		# The kicked guest's session is restored before the frame that returns
		# them to the shared room lands, so wait for both to settle.
		_check(
			await _wait(
				func() -> bool:
					return not state.read_only and not state.is_visiting() and api.realtime._room == "campus",
				40
			),
			"kicked_guest_returns_home"
		)
		_mark("visit_kicked_checked")
