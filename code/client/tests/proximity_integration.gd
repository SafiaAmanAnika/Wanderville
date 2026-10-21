extends SceneTree
var failures := 0
var api: Node
var session: Node
var stage: Node2D
var ui: Node
var role := ""
var output := ""
var heard := false
var got_chat := false

func check(value: bool, label: String) -> void:
	print("PROXIMITY_CHECK ", role, " ", label, " ", "PASS" if value else "FAIL")
	if not value:
		failures += 1

func mark(label: String) -> void:
	var file := FileAccess.open(output.path_join(role + "_" + label), FileAccess.WRITE)
	file.store_string("ready")

func barrier(label: String) -> void:
	mark(label)
	var other := "bob" if role == "alice" else "alice"
	var deadline := Time.get_ticks_msec() + 15000
	while not FileAccess.file_exists(output.path_join(other + "_" + label)) and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout
	check(FileAccess.file_exists(output.path_join(other + "_" + label)), label + "_barrier")

func shot(label: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(role + "_" + label + ".png"))

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	api = root.get_node("APIClient")
	session = root.get_node("Global")
	role = OS.get_environment("WANDERVILLE_TEST_ROLE")
	output = OS.get_environment("WANDERVILLE_TEST_SYNC")
	var login: Dictionary = await api.login("integration_" + role, OS.get_environment("WANDERVILLE_TEST_PASSWORD"))
	check(login.get("ok", false), "login")
	if not login.get("ok", false):
		quit(1)
		return
	var credentials: Dictionary = api.data_of(login)
	session.set_session(credentials["access_token"], credentials["player"], credentials["refresh_token"])
	stage = Node2D.new()
	root.add_child(stage)
	current_scene = stage
	check(load("res://Scenes/social_standalone.tscn") != null, "standalone_scene_loads")
	ui = load("res://Scripts/social/proximity_social.gd").new()
	stage.add_child(ui)
	api.realtime.standalone_enabled = true
	api.realtime.nearby_message_received.connect(func(message: Dictionary) -> void:
		if message["body"] == "native hello":
			got_chat = true
	)
	for _i in 100:
		if api.realtime.connected:
			break
		await create_timer(0.05).timeout
	check(api.realtime.connected and not api.realtime.connection_id.is_empty(), "v2_connected")
	await barrier("connected")
	var found: Dictionary = await api.authenticated(HTTPClient.METHOD_GET, "/social/search?q=integration_" + ("bob" if role == "alice" else "alice"))
	var target := int(api.data_of(found)[0]["id"])
	if role == "alice":
		var response: Dictionary = await api.authenticated(HTTPClient.METHOD_POST, "/social/requests", {"target_id": target})
		check(response.get("ok", false), "friend_request")
	await barrier("requested")
	if role == "bob":
		var response: Dictionary = await api.authenticated(HTTPClient.METHOD_POST, "/social/friends/%d" % target, {"action": "accept"})
		check(response.get("ok", false), "friend_accept")
	await barrier("friends")
	await create_timer(0.5).timeout
	check(ui._peers.size() == 1 and ui._peers[0].get("show_prompt", false), "friend_prompt")
	if role == "alice":
		ui._text.text = "native hello"
		await ui._send("native hello")
		check(ui._text.text.is_empty(), "websocket_text_ack")
	await barrier("chat")
	await create_timer(0.3).timeout
	check(got_chat and ui._bubbles.size() == 1, "speech_bubble")
	await shot("nearby")
	await ui.voice.join_voice()
	for _i in 100:
		if ui.voice._ready_audio:
			break
		await create_timer(0.05).timeout
	check(ui.voice._ready_audio and ui.voice.muted and ui.voice._capture == null, "voice_join_microphone_off")
	await barrier("voice")
	if role == "alice":
		await api.realtime.command("voice.state", {"session_id": ui.voice.session_id, "muted": false})
		var frame := PackedByteArray()
		frame.resize(1920)
		for i in 960:
			frame.encode_s16(i * 2, 4000)
		for _i in 40:
			ui.voice._socket.send(frame)
			await create_timer(0.02).timeout
	else:
		for _i in 60:
			heard = heard or ui.voice.output_level > 0.01
			await create_timer(0.02).timeout
		check(heard, "real_native_pcm_received")
	await barrier("audio")
	# A quiet room must cost nothing on the wire and must not look like a dead
	# connection: the server suppresses the frames of silence and keeps the
	# session alive with a small keepalive instead. The keepalive interval is
	# five seconds by default, so the wait has to outlast it.
	if role == "bob":
		await create_timer(0.5).timeout
		var idle_frames: int = ui.voice.frames_received
		var idle_keepalives: int = ui.voice.keepalives_received
		await create_timer(6.0).timeout
		check(ui.voice.frames_received == idle_frames, "idle_room_sends_no_audio")
		check(ui.voice.keepalives_received > idle_keepalives, "idle_room_is_kept_alive")
		check(ui.voice._ready_audio, "idle_room_keeps_voice_alive")
	await barrier("idle")
	ui.voice.leave()
	await ui.community.open_for()
	ui.community._view.select(0)
	ui.community.select_code("wheat_seed")
	ui.community._quantity.value = 2
	await ui.community._save()
	await create_timer(0.3).timeout
	check(ui.community._rows.size() == 1, "native_wishlist_save")
	await barrier("wishlists")
	if role == "alice":
		await ui.community.open_for(target)
		await create_timer(0.3).timeout
		ui.community._items.select(0)
		ui.community._select(0)
		ui.community._quantity.value = 1
		ui.community._prepare_gift()
		check(ui.community._confirm.visible, "gift_confirmation")
		await shot("gift")
		ui.community._confirm.hide()
		var gift_id: String = ui.community._proposal["request_id"]
		await api.authenticated(HTTPClient.METHOD_POST, "/integration/lose-next-gift-response")
		ui.community._send_gift()
		await create_timer(0.5).timeout
		check(not ui.community._pending().is_empty(), "lost_gift_response_keeps_id")
		await ui.community._recover()
		var receipt: Dictionary = await api.authenticated(HTTPClient.METHOD_GET, "/social/gifts/requests/" + gift_id)
		check(ui.community._pending().is_empty() and api.data_of(receipt).get("found", false), "gift_receipt_reconciled")
	await barrier("gift")
	if role == "bob":
		ui.community._view.select(2)
		await ui.community.refresh()
		check(ui.community._rows.size() == 1, "gift_inbox")
		if not ui.community._rows.is_empty():
			ui.community._items.select(0)
			await ui.community._claim()
			await create_timer(0.2).timeout
			check(ui.community._rows.is_empty(), "native_gift_claim")
	await barrier("done")
	ui.community._close()
	api.realtime.stop()
	check(ui.voice.session_id.is_empty() and ui._bubbles.is_empty(), "disconnect_cleanup")
	print("PROXIMITY_RESULT ", role, " failures=", failures)
	quit(0 if failures == 0 else 1)
