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

func wait_store(store: Node) -> void:
	for index in range(100):
		if not store._busy:
			return
		await create_timer(0.1).timeout
	check(false, "store_request_completes")

func choose(store: Node, code: String, selling := false) -> void:
	store.get_node("%Mode").select(1 if selling else 0)
	store._selected_code = code
	store.get_node("%Quantity").value = 1
	store._render()

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
	if OS.get_environment("WANDERVILLE_TEST_RESTART") == "1":
		var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output.path_join("restart.json")))
		check(not api.pending_shop().is_empty(), "restart_retains_pending_transaction")
		var restored: Node = load("res://Scenes/store_panel.tscn").instantiate()
		root.add_child(restored)
		await restored.open_store()
		check(JSON.stringify(state.inventory) == saved["inventory"] and int(state.economy["aura_balance"]) == int(saved["aura"]) and restored._claimed, "process_restart_restores_inventory_balance_grant")
		check(api.pending_shop().is_empty(), "process_restart_reconciles_committed_sale")
		check(state.farm_plots.size() == 1 and state.farm_plots[0]["item_code"] == "wheat", "process_restart_preserves_planted_crop")
		check(int(state.experience["total_xp"]) == 2100 and int(state.experience["level"]) == 10 and state.experience["rewards"].size() == 2, "process_restart_preserves_xp_level_rewards")
		print("HUD_RESTART_RESULT failures=", failures)
		quit(0 if failures == 0 else 1)
		return
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
	await hud.switch_panel("")
	hud.get_node("%StoreButton").pressed.emit()
	var store: Node = hud.get_node("%Store")
	await wait_store(store)
	check(hud.active == "store" and store._loaded, "hud_store_button_opens")
	check(hud.get_node("%StoreButton").get_global_rect().end.x <= 800, "store_icon_small_viewport_bounds")
	await store._claim()
	check(store._claimed and state.seed_inventory.size() == 2 and state.seed_inventory["wheat"] == 8 and int(state.inventory_summary["capacity"]) == 33, "starter_basics_fit_preserve_existing")
	check(store._catalog.filter(func(item: Dictionary) -> bool: return item.get("category") == "seed").size() >= 20, "recovered_catalog_preserved")
	response = await api.authenticated(HTTPClient.METHOD_POST, "/shop/starter/claim", {})
	await state.refresh_gameplay()
	check(api.data_of(response).get("already_claimed", false) and state.seed_inventory["wheat"] == 8, "starter_replay_no_duplicate")
	choose(store, "paddy_seed")
	var aura_before := int(state.economy["aura_balance"])
	var price := int(store._selected()["buy_value"])
	store._trade()
	store._trade()
	await wait_store(store)
	check(state.seed_inventory["paddy"] == 6 and int(state.economy["aura_balance"]) == aura_before - price, "buy_double_click_charged_once")
	store.get_node("%Quantity").value = 99
	check(store.get_node("%Trade").disabled and store.get_node("%Details").text.contains("Not enough Aura"), "store_insufficient_funds_disabled")
	choose(store, "paddy_seed", true)
	await store._trade()
	check(state.seed_inventory["paddy"] == 5 and int(state.economy["aura_balance"]) == aura_before - price + 1 and int(state.experience["total_xp"]) == 0, "store_sale_no_seed_resale_xp")
	choose(store, "wheat_seed")
	aura_before = int(state.economy["aura_balance"])
	price = int(store._selected()["buy_value"])
	await api.authenticated(HTTPClient.METHOD_POST, "/integration/lose-next-shop-response", {})
	await store._trade()
	check(state.seed_inventory["wheat"] == 9 and int(state.economy["aura_balance"]) == aura_before - price and api.pending_shop().is_empty() and store.get_node("%Status").text.contains("confirmed by the server"), "lost_purchase_response_reconciled_once")
	await shot("store_800x600")
	await api.authenticated(HTTPClient.METHOD_POST, "/integration/stack-fixture", {})
	await state.refresh_gameplay()
	choose(store, "wheat_seed", true)
	check(int(store._selected().get("owned", 0)) == 109, "store_aggregates_owned_stacks")
	await hud.switch_panel("inventory")
	await settle()
	check(hud.get_node("%Items").item_count == 4 and hud.get_node("%Capacity").text.contains("4 / 33"), "inventory_multistacks_shared_capacity")
	hud._select_item(1)
	var selected_stack: String = hud._inventory_selection
	hud._render_inventory(true)
	check(hud._inventory_selection == selected_stack and hud.get_node("%Items").get_selected_items().size() == 1, "inventory_selection_keeps_stack_identity")
	hud.get_node("%Category").select(2)
	hud._render_inventory(true)
	check(hud.get_node("%Items").item_count == 0 and hud.get_node("%Capacity").text.contains("4 / 33"), "category_filter_does_not_change_capacity")
	hud.get_node("%Category").select(0)
	hud._render_inventory(true)
	await shot("inventory_stacks_800x600")
	await hud.switch_panel("")
	picker.show_menu()
	check(picker.grid.get_child_count() == 3, "picker_combines_stacks_owned_only")
	var restricted := 0
	for button in picker.grid.get_children():
		if button.disabled:
			restricted += 1
		if button.get_meta("item_code") == "wheat_seed":
			check(button.text.contains("109") and not button.disabled, "purchased_seed_immediately_selectable")
		if button.get_meta("item_code") == "potato_seed":
			check(button.text.contains("4") and button.text.to_lower().contains("winter"), "picker_level_and_season_separate_reasons")
	check(restricted > 0, "picker_season_restrictions_visible")
	await shot("restored_seed_picker_800x600")
	picker.get_node("%Store").pressed.emit()
	await wait_store(store)
	check(hud.active == "store" and not picker.visible, "picker_store_link")
	await hud.switch_panel("")
	# Use the actual controller and picker on a minimal stage, without editing or
	# loading the supplied large map. The controller retains its world coordinates.
	var map := Node2D.new()
	map.name = "Map"
	var layer := TileMapLayer.new()
	layer.name = "FarmLayer"
	map.add_child(layer)
	stage.add_child(map)
	var farm := Node2D.new()
	farm.set_script(load("res://Scripts/farm_controller.gd"))
	var farm_picker: Node = load("res://Scenes/seed_picker_menu.tscn").instantiate()
	farm.add_child(farm_picker)
	stage.add_child(farm)
	await farm._till(Vector2i(0, 0))
	farm._plant(Vector2i(0, 0), "0,0")
	for button in farm_picker.grid.get_children():
		if button.get_meta("item_code") == "wheat_seed":
			button.pressed.emit()
			button.pressed.emit()
	for index in range(100):
		if state.seed_inventory.get("wheat", 0) == 108 and farm.active_crops.has("0,0"):
			break
		await create_timer(0.1).timeout
	await state.refresh_gameplay()
	check(state.seed_inventory["wheat"] == 108 and farm.active_crops.get("0,0", {}).get("type") == "wheat" and int(state.experience["total_xp"]) == 1, "picker_controller_repeated_plant_consumes_once")
	await api.refill_water()
	await state.refresh_gameplay()
	await farm._water(Vector2i(0, 0), "0,0")
	await create_timer(19.0).timeout
	await state.refresh_gameplay()
	check(farm.active_crops["0,0"]["stage"] == 4, "existing_crop_grows_after_one_watering")
	await farm._harvest(Vector2i(0, 0), "0,0")
	check(int(state.experience["total_xp"]) == 21 and not farm.active_crops.has("0,0"), "first_harvest_produce_and_twenty_xp")
	await hud.switch_panel("store")
	await wait_store(store)
	choose(store, "wheat", true)
	check(not store.get_node("%Trade").disabled, "starter_produce_sellable_level_one")
	aura_before = int(state.economy["aura_balance"])
	await store._trade()
	check(int(state.experience["total_xp"]) == 26 and int(state.economy["aura_balance"]) == aura_before + 12, "produce_sale_aura_and_five_xp")
	choose(store, "wheat_seed")
	aura_before = int(state.economy["aura_balance"])
	await store._trade()
	check(state.seed_inventory["wheat"] == 109 and int(state.economy["aura_balance"]) == aura_before - 6, "complete_loop_rebuys_seed")
	await hud.switch_panel("")
	await farm._on_seed_selected("wheat")
	await api.authenticated(HTTPClient.METHOD_POST, "/integration/progress/%d" % (120 - int(state.experience["total_xp"])), {})
	await state.refresh_gameplay()
	check(hud.get_node("%Balance").text.contains("Level 2") and hud.get_node("%Balance").text.contains("Villager") and hud.get_node("%ProgressText").text.contains("40 / 100") and hud.get_node("%XP").max_value == 100 and hud.get_node("%XP").value == 40, "hud_authoritative_level_title_span")
	check(hud.get_node("%LevelToast").visible and hud.get_node("%LevelToastText").text.contains("+3 inventory slots") and hud.get_node("%LevelToastText").text.contains("+25 Aura") and hud.get_node("%LevelToastText").text.contains("Sugarcane"), "level_toast_actual_slots_aura_unlocks")
	check(int(state.inventory_summary["capacity"]) == 36, "level_increases_shared_capacity")
	await shot("level_two_800x600")
	hud.get_node("%ToastClose").pressed.emit()
	await state.refresh_gameplay()
	check(not hud.get_node("%LevelToast").visible, "poll_does_not_repeat_level_toast")
	await api.authenticated(HTTPClient.METHOD_POST, "/integration/progress/1980", {})
	await state.refresh_gameplay()
	check(hud.get_node("%Balance").text.contains("Level 10 — Landkeeper") and hud.get_node("%ProgressText").text == "Max level" and hud.get_node("%XP").value == hud.get_node("%XP").max_value, "max_level_hud_without_level_eleven")
	check(int(state.inventory_summary["capacity"]) == 76 and hud.get_node("%LevelToastText").text.contains("+40 inventory slots") and hud.get_node("%LevelToastText").text.contains("+100 Aura"), "multi_level_jump_exact_rewards")
	await shot("max_level_800x600")
	await hud.switch_panel("store")
	await wait_store(store)
	choose(store, "paddy_seed")
	aura_before = int(state.economy["aura_balance"])
	var seeds_before := int(state.seed_inventory["paddy"])
	# Only the runner's isolated Godot save directory may be used for this fault.
	if OS.get_user_data_dir().contains("WandervilleVerification"):
		store._trade()
		var saved_path := ProjectSettings.globalize_path("user://shop_pending.cfg")
		var backup_path := saved_path + ".test-backup"
		check(DirAccess.rename_absolute(saved_path, backup_path) == OK, "receipt_fixture_preserves_saved_file")
		check(DirAccess.make_dir_absolute(saved_path) == OK, "receipt_fixture_blocks_file_clear")
		await wait_store(store)
		check(not store._busy and store.get_node("%Status").text.to_lower().contains("confirmed") and store.get_node("%Retry").disabled, "receipt_clear_failure_stops_automatic_retry")
		check(DirAccess.remove_absolute(saved_path) == OK and DirAccess.rename_absolute(backup_path, saved_path) == OK, "receipt_fixture_restores_saved_file")
		await store.open_store()
		check(api.pending_shop().is_empty() and state.seed_inventory["paddy"] == seeds_before + 1 and int(state.economy["aura_balance"]) == aura_before - 5, "receipt_clear_recovery_does_not_charge_again")
	else:
		check(false, "receipt_fault_requires_isolated_directory")
	await api.authenticated(HTTPClient.METHOD_POST, "/integration/fill-inventory", {})
	await state.refresh_gameplay()
	choose(store, "wheat_seed")
	store.get_node("%Quantity").value = 4
	check(store.get_node("%Trade").disabled and store.get_node("%Details").text.contains("Inventory full"), "store_full_capacity_rejects_new_stack")
	store.get_node("%Quantity").value = 3
	check(not store.get_node("%Trade").disabled, "store_full_capacity_accepts_partial_stack")
	aura_before = int(state.economy["aura_balance"])
	await store._trade()
	check(int(state.inventory_summary["used_slots"]) == int(state.inventory_summary["capacity"]) and int(state.economy["aura_balance"]) == aura_before - 18, "partial_stack_purchase_confirmed_at_full_capacity")
	var saved_inventory: String = JSON.stringify(state.inventory)
	var saved_aura := int(state.economy["aura_balance"])
	await api.logout()
	await settle()
	check(hud._notices.is_empty() and hud.get_node("%Items").item_count == 0 and social._private.is_empty() and social.message.text == "" and hud.active == "", "logout_private_state_cleared")
	response = await api.login("integration_alice", OS.get_environment("WANDERVILLE_TEST_PASSWORD"))
	login = api.data_of(response)
	session.set_session(login["access_token"], login["player"], login["refresh_token"])
	await state.load_from_backend()
	await store.open_store()
	check(JSON.stringify(state.inventory) == saved_inventory and int(state.economy["aura_balance"]) == saved_aura and store._claimed, "relogin_restores_inventory_balance_grant")
	# Simulate exiting after the server committed, before clearing the saved ID.
	var pending := {"action": "sell", "item_code": "paddy_seed", "quantity": 1, "request_id": "restart-sale-fixture"}
	check(api.save_pending_shop(pending), "pending_transaction_saved_to_disk")
	response = await api.authenticated(HTTPClient.METHOD_POST, "/shop/sell", pending)
	check(response.get("ok", false), "restart_sale_committed")
	await state.refresh_gameplay()
	var saved_file := FileAccess.open(output.path_join("restart.json"), FileAccess.WRITE)
	saved_file.store_string(JSON.stringify({"inventory": JSON.stringify(state.inventory), "aura": state.economy["aura_balance"]}))
	saved_file.close()
	print("HUD_RESULT failures=", failures)
	quit(0 if failures == 0 else 1)
