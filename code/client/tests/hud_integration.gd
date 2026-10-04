extends SceneTree

var failures := 0
var api: Node
var session: Node
var state: Node
var hud: Node
var output := ""

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	print("HUD_CHECK ", label, " ", "PASS" if ok else "FAIL")
	if not ok:
		failures += 1

func settle() -> void:
	await create_timer(0.4).timeout

func shot(name: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(name + ".png"))

func _run() -> void:
	api = root.get_node("APIClient")
	session = root.get_node("Global")
	state = root.get_node("GameState")
	output = OS.get_environment("WANDERVILLE_TEST_SYNC")
	var response: Dictionary = await api.login("integration_alice", OS.get_environment("WANDERVILLE_TEST_PASSWORD"))
	if not response.get("ok", false):
		quit(2)
		return
	var login: Dictionary = api.data_of(response)
	session.set_session(login["access_token"], login["player"], login["refresh_token"])
	check(await state.load_from_backend(), "real_backend_state")
	# Real UI scenes, a lightweight background, and the supplied player artwork.
	# This is explicitly UI rendering, separate from full-world gameplay checks.
	var stage := Node2D.new()
	root.add_child(stage)
	current_scene = stage
	var background := Polygon2D.new()
	background.polygon = PackedVector2Array([Vector2.ZERO, Vector2(2000, 0), Vector2(2000, 1200), Vector2(0, 1200)])
	background.color = Color(0.19, 0.32, 0.19)
	stage.add_child(background)
	var avatar: Node2D = load("res://Scenes/player1.tscn").instantiate()
	avatar.position = Vector2(330, 500)
	avatar.scale = Vector2(5, 5)
	avatar.process_mode = Node.PROCESS_MODE_DISABLED
	stage.add_child(avatar)
	hud = load("res://Scenes/world_hud.tscn").instantiate()
	stage.add_child(hud)
	await settle()
	check(hud.active == "" and not state.social_open, "initial_compact_hud")
	check(hud.get_node("%Balance").text.contains("Aura %d" % int(state.economy["aura_balance"])) and hud.get_node("%Balance").text.contains("Level %d" % int(state.experience["level"])), "authoritative_counters")
	for kind in ["social", "inventory", "notifications", "settings"]:
		await hud.switch_panel(kind)
		await settle()
		check(hud.active == kind and state.social_open, kind + "_opens_blocks_world")
		await shot(kind)
		await hud.switch_panel(kind)
		check(hud.active == "" and not state.social_open, kind + "_toggle_closes")
	await hud.switch_panel("social")
	var social: Node = hud.get_node("%SocialPanel")
	social.message.text = "unsent nearby draft"
	social._toggle(false)
	social._toggle(true)
	check(social.message.text == "unsent nearby draft", "social_tab_draft_preserved")
	await hud.switch_panel("inventory")
	await hud.switch_panel("social")
	check(social.message.text == "unsent nearby draft", "social_close_draft_preserved")
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	hud._input(escape)
	await settle()
	check(hud.active == "" and not state.social_open, "escape_closes_restores_input")
	await hud.switch_panel("inventory")
	await settle()
	check(hud.get_node("%Items").item_count == 1 and hud.get_node("%Items").get_item_text(0).contains("×3"), "inventory_real_quantity")
	check(hud.get_node("%Items").get_item_icon(0) is AtlasTexture, "crop_icon_uses_atlas_region")
	check(WoodPanel.item_icon("missing_artwork") is Texture2D, "missing_artwork_placeholder")
	hud._select_item(0)
	check(hud.get_node("%ItemDetails").text.contains("Wheat"), "inventory_selection_details")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	hud.get_node("%Outside").gui_input.emit(mouse)
	await settle()
	check(hud.active == "" and not state.social_open, "outside_click_closes")
	await hud.switch_panel("notifications")
	await settle()
	check(hud._notice_unread == 35 and hud._notices.size() == 30, "notifications_real_badge_no_bulk_read")
	await hud.refresh_notifications(true)
	check(hud._notices.size() == 35 and hud._cursor == null, "notifications_cursor_pagination")
	await hud._view_notice(0)
	check(hud._notice_unread == 34, "view_marks_only_selected_read")
	await hud._update_notice(true)
	check(hud._notices.size() == 34 and hud._notice_unread == 34, "dismiss_updates_server_and_badge")
	await hud.switch_panel("settings")
	var settings: Node = hud.get_node("%Settings")
	settings.get_node("%MusicSlider").value = 37
	settings.get_node("%SFXSlider").value = 43
	await hud.switch_panel("")
	response = await api.authenticated(HTTPClient.METHOD_GET, "/profile")
	check(api.data_of(response)["music_volume"] == 37 and api.data_of(response)["effects_volume"] == 43, "settings_persist_to_api")
	await hud.switch_panel("settings")
	var original_url: String = api.base_url
	api.base_url = "http://127.0.0.1:1"
	await hud.switch_panel("")
	check(hud.active == "settings" and not settings.get_node("%SaveStatus").text.is_empty(), "settings_failure_visible_panel_retained")
	api.base_url = original_url
	await hud.switch_panel("")
	var picker: Node = load("res://Scenes/seed_picker_menu.tscn").instantiate()
	stage.add_child(picker)
	await picker.show_menu()
	await settle()
	check(picker.grid.get_child_count() > 0 and picker.grid.get_child(0).icon is AtlasTexture, "existing_seed_picker_icons")
	await shot("seed_picker")
	var quantity: int = state.seed_inventory["wheat"]
	picker.hide_menu()
	check(state.seed_inventory["wheat"] == quantity and not state.menu_open, "seed_cancel_no_inventory_mutation")
	var cycle := CanvasModulate.new()
	cycle.set_script(load("res://Scripts/day_and_night_cycle.gd"))
	stage.add_child(cycle)
	cycle.set_process(false)
	cycle.time_elapsed = 0.25 * cycle.CYCLE_LENGTH
	cycle._update_animation()
	var daylight: Color = cycle.color
	cycle.time_elapsed = 0.85 * cycle.CYCLE_LENGTH
	cycle._update_animation()
	check(cycle.color != daylight and cycle.CYCLE_LENGTH == 2400.0, "day_night_visible_40minute_cycle")
	await shot("night_hud")
	cycle.color = Color.WHITE
	# Exercise the same weather attachment hook on small particles, avoiding the
	# supplied map's very large GPU particle systems in this UI-only rendering run.
	var weather_map := Node2D.new()
	var manager := Node2D.new()
	manager.name = "WeatherManager"
	manager.set_script(load("res://Scripts/weather_manager.gd"))
	weather_map.add_child(manager)
	var effects := Node2D.new()
	effects.name = "WeatherFXManager"
	for name in ["Rain", "Snow", "Autumn_leaves", "Spring_leaves"]:
		var particle := GPUParticles2D.new()
		particle.name = name
		particle.amount = 1
		effects.add_child(particle)
	weather_map.add_child(effects)
	stage.add_child(weather_map)
	check(effects.get_script() != null, "existing_weather_effects_hook_attached")
	for season in ["summer", "autumn", "winter", "spring"]:
		var weather := "snow" if season == "winter" else "rain"
		state.world_updated.emit({"current_season": season, "weather": weather})
		check(effects.get_node("Autumn_leaves").emitting == (season == "autumn") and effects.get_node("Spring_leaves").emitting == (season == "spring") and effects.get_node("Snow").emitting == (season == "winter") and effects.get_node("Rain").emitting == (season != "winter"), "season_weather_" + season)
	state.world_updated.emit(state.world_state)
	root.content_scale_size = Vector2i(800, 600)
	root.size = Vector2i(800, 600)
	await hud.switch_panel("inventory")
	await settle()
	check(hud.get_node("%PanelArea").get_global_rect().end.x <= 800 and hud.get_node("%PanelArea").position.x >= 0, "small_viewport_panel_bounds")
	await shot("inventory_800x600")
	await hud.switch_panel("social")
	await settle()
	await shot("social_800x600")
	await hud.switch_panel("settings")
	await settle()
	await shot("settings_800x600")
	await api.logout()
	await settle()
	check(hud._notices.is_empty() and hud.get_node("%Items").item_count == 0 and social._private.is_empty() and social.message.text == "" and hud.active == "", "logout_private_state_cleared")
	print("HUD_RESULT failures=", failures)
	quit(0 if failures == 0 else 1)
