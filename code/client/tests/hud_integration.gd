extends SceneTree

var failures := 0
var api: Node
var session: Node
var state: Node
var hud: Node
var social: Node
var stage: Node
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

# The storage menu is the single inventory + buy/sell UI now.
func open_storage(section := "") -> Node:
	var menu: Node = load("res://Scripts/inventory/storage_menu.gd").new()
	menu.start_section = section
	# The bag itself is view-only; the trade controls are what these checks drive.
	menu.mode = "trade"
	stage.add_child(menu)
	return menu

func wait_menu(menu: Node) -> void:
	for index in range(100):
		if not menu._busy:
			return
		await create_timer(0.1).timeout
	check(false, "storage_request_completes")

# select an item and trade amount inside an open storage section
func pick(menu: Node, code: String, qty := 1) -> void:
	menu._selected = code
	menu._qty = qty
	menu._status.text = ""
	menu._render_section()

func wait_until(ready: Callable, label: String) -> void:
	for index in range(100):
		if ready.call():
			return
		await create_timer(0.1).timeout
	check(false, label)

func owned(code: String) -> int:
	var total := 0
	for row in state.inventory:
		if str(row["item_code"]) == code:
			total += int(row["quantity"])
	return total

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
		check(JSON.stringify(state.inventory) == saved["inventory"] and int(state.economy["aura_balance"]) == int(saved["aura"]), "process_restart_restores_inventory_balance")
		check(state.farm_plots.size() == 1 and state.farm_plots[0]["item_code"] == "wheat", "process_restart_preserves_planted_crop")
		check(int(state.experience["total_xp"]) == 2100 and int(state.experience["level"]) == 10 and state.experience["rewards"].size() == 2, "process_restart_preserves_xp_level_rewards")
		print("HUD_RESTART_RESULT failures=", failures)
		quit(0 if failures == 0 else 1)
		return
	# Real UI scenes, a lightweight background, and the supplied player artwork.
	# This is explicitly UI rendering, separate from full-world gameplay checks.
	stage = Node2D.new()
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
	check(hud.get_node("%SocialButton").text == "Social Lobby", "visit_social_lobby_action")
	await hud.switch_panel("settings")
	await settle()
	check(hud.active == "settings" and state.social_open, "settings_opens_blocks_world")
	await shot("settings")
	await hud.switch_panel("settings")
	check(hud.active == "" and not state.social_open, "settings_toggle_closes")
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	await hud.switch_panel("settings")
	await settle()
	hud._input(escape)
	await settle()
	check(hud.active == "" and not state.social_open, "escape_closes_restores_input")
	# Social lives in the Social Lobby now; the shared panel still owns the
	# notification inbox, so exercise it directly against the real backend.
	social = load("res://Scenes/social_panel.tscn").instantiate()
	stage.add_child(social)
	await settle()
	await social.refresh_notifications()
	check(social._notice_unread == 35 and social._notices.size() == 30, "notifications_real_badge_no_bulk_read")
	await social.refresh_notifications(true)
	check(social._notices.size() == 35 and social._cursor == null, "notifications_cursor_pagination")
	await social._view_notice(0)
	check(social._notice_unread == 34, "view_marks_only_selected_read")
	await social._update_notice(true)
	check(social._notices.size() == 34 and social._notice_unread == 34, "dismiss_updates_server_and_badge")
	# The storage menu replaces the old bag panel: it lists the seeds section
	# with the real stack counts, icon and Aura / slot header.
	var storage: Node = open_storage("seeds")
	await settle()
	check(storage._section == "seeds" and storage._grid.get_child_count() > 0, "storage_opens_seed_section")
	check(storage._selected == "wheat_seed" and storage._info.text.contains("You have: 3"), "storage_real_quantity")
	check(storage._icon.texture is AtlasTexture, "crop_icon_uses_atlas_region")
	check(WoodPanel.item_icon("missing_artwork") is Texture2D, "missing_artwork_placeholder")
	check(storage._aura_text().contains("Aura %d" % int(state.economy["aura_balance"])) and storage._aura_text().contains("Slots"), "storage_header_aura_and_capacity")
	storage.close()
	await settle()
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
	cycle.set_script(load("res://Scripts/day_night_cycle.gd"))
	stage.add_child(cycle)
	cycle.set_process(false)
	cycle.elapsed_time = 0.25 * cycle.daytime_duration
	cycle.update_lighting()
	var daylight: Color = cycle.color
	cycle.elapsed_time = cycle.daytime_duration + 0.5 * cycle.nighttime_duration
	cycle.update_lighting()
	check(cycle.color != daylight and cycle.is_nighttime()
		and cycle.daytime_duration + cycle.nighttime_duration == 1800.0, "day_night_visible_30minute_cycle")
	await shot("night_hud")
	cycle.color = Color.WHITE
	# Drive the seasonal effects script on small particles, avoiding the supplied
	# map's very large GPU particle systems in this UI-only rendering run. It is
	# kept out of the tree so _ready does not touch the real user://seasonal_state.cfg.
	var effects := Node2D.new()
	effects.set_script(load("res://Scripts/seasonal_effects.gd"))
	for name in ["Rain", "Snow", "Autumn_leaves", "Spring_leaves"]:
		var particle := GPUParticles2D.new()
		particle.name = name
		particle.amount = 1
		effects.add_child(particle)
	effects.rain = effects.get_node("Rain")
	effects.snow = effects.get_node("Snow")
	effects.autumn_leaves = effects.get_node("Autumn_leaves")
	effects.spring_leaves = effects.get_node("Spring_leaves")
	check(effects.get_script() != null, "existing_weather_effects_hook_attached")
	# A rain_elapsed_time of one interval is the first moment a shower is scheduled.
	effects.rain_elapsed_time = effects.RAIN_INTERVAL
	for season in range(4):
		effects.current_season = season
		effects.update_season_effects()
		check(effects.autumn_leaves.emitting == (season == 1) and effects.spring_leaves.emitting == (season == 3) and effects.snow.emitting == (season == 2) and effects.rain.emitting == (season == 0), "season_weather_" + effects.get_season_name().to_lower())
	effects.free()
	state.world_updated.emit(state.world_state)
	root.content_scale_size = Vector2i(800, 600)
	root.size = Vector2i(800, 600)
	await hud.switch_panel("settings")
	await settle()
	check(hud.get_node("%Settings").get_global_rect().end.x <= 800 and hud.get_node("%Settings").get_global_rect().position.x >= 0, "small_viewport_settings_bounds")
	await shot("settings_800x600")
	await hud.switch_panel("")
	# Starter seeds are claimed straight from the API; the storage menu is the
	# only place to buy, sell and set the trade amount.
	response = await api.authenticated(HTTPClient.METHOD_POST, "/shop/starter/claim", {})
	check(response.get("ok", false), "starter_claim")
	await state.refresh_gameplay()
	check(state.seed_inventory.size() == 2 and state.seed_inventory["wheat"] == 8 and int(state.inventory_summary["capacity"]) == 33, "starter_basics_fit_preserve_existing")
	response = await api.authenticated(HTTPClient.METHOD_POST, "/shop/starter/claim", {})
	await state.refresh_gameplay()
	check(api.data_of(response).get("already_claimed", false) and state.seed_inventory["wheat"] == 8, "starter_replay_no_duplicate")
	storage = open_storage("seeds")
	pick(storage, "paddy_seed")
	var aura_before := int(state.economy["aura_balance"])
	var price := int(storage._item("paddy_seed")["buy"])
	storage._trade("buy")
	storage._trade("buy")
	await wait_menu(storage)
	check(state.seed_inventory["paddy"] == 6 and int(state.economy["aura_balance"]) == aura_before - price, "buy_double_click_charged_once")
	pick(storage, "paddy_seed", 99)
	check(storage._buy.disabled and storage._price.text.contains("Not enough Aura"), "store_insufficient_funds_disabled")
	pick(storage, "paddy_seed")
	await storage._trade("sell")
	check(state.seed_inventory["paddy"] == 5 and int(state.economy["aura_balance"]) == aura_before - price + 1 and int(state.experience["total_xp"]) == 0, "store_sale_no_seed_resale_xp")
	# amount selector: -/+ steps between 1 and the server maximum of 99
	storage._step_qty(1)
	check(storage._qty == 2 and storage._qty_label.text == "2", "storage_amount_steps_up")
	storage._step_qty(-1)
	check(storage._qty == 1 and storage._qty_less.disabled, "storage_amount_minimum_one")
	pick(storage, "paddy_seed", 98)
	storage._step_qty(1)
	check(storage._qty == 99 and storage._qty_more.disabled, "storage_amount_maximum_ninety_nine")
	pick(storage, "wheat_seed")
	check(not storage._sell.disabled and storage._price.text.contains("Aura each") and not storage._price.text.contains("for ×"), "storage_price_shows_unit_prices")
	await shot("storage_seeds_800x600")
	# A lost committed response is only visible as an error; the next state
	# refresh shows the item the server already charged for.
	pick(storage, "wheat_seed")
	aura_before = int(state.economy["aura_balance"])
	var wheat_seeds := int(state.seed_inventory["wheat"])
	price = int(storage._item("wheat_seed")["buy"])
	await api.authenticated(HTTPClient.METHOD_POST, "/integration/lose-next-shop-response", {})
	await storage._trade("buy")
	check(storage._status.text.contains("Fixture lost committed response"), "lost_purchase_response_visible_to_player")
	await state.refresh_gameplay()
	check(state.seed_inventory["wheat"] == wheat_seeds + 1 and int(state.economy["aura_balance"]) == aura_before - price, "lost_purchase_response_reconciled_by_poll")
	await api.authenticated(HTTPClient.METHOD_POST, "/integration/stack-fixture", {})
	await state.refresh_gameplay()
	pick(storage, "wheat_seed")
	check(storage._owned("wheat_seed") == 109, "storage_aggregates_owned_stacks")
	await shot("storage_stacks_800x600")
	storage.close()
	await settle()
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
	var before_children := stage.get_child_count()
	picker.get_node("%Storage").pressed.emit()
	await settle()
	check(not picker.visible and stage.get_child_count() == before_children + 1, "picker_storage_link")
	var linked: Node = stage.get_child(stage.get_child_count() - 1)
	check(linked != null and linked._section == "seeds", "picker_storage_opens_seed_section")
	linked.close()
	await settle()
	# Use the actual controller and picker on a minimal stage, without editing or
	# loading the supplied large map. The controller retains its world coordinates.
	var map := Node2D.new()
	map.name = "Map"
	var field := Node2D.new()
	field.name = "FarmField"
	map.add_child(field)
	var layer := TileMapLayer.new()
	layer.name = "FarmLayer"
	field.add_child(layer)
	# The controller sizes its 17 x 21 grid from this rectangle, as in map2.tscn.
	var zone := Area2D.new()
	zone.name = "FarmZone"
	field.add_child(zone)
	var zone_shape := CollisionShape2D.new()
	zone_shape.name = "CollisionShape2D"
	zone_shape.shape = RectangleShape2D.new()
	zone_shape.shape.size = Vector2(17, 21) * 50.0
	zone.add_child(zone_shape)
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
	# Harvested produce is sold from the storage menu's crops shelf.
	storage = open_storage("crops")
	pick(storage, "wheat")
	check(not storage._sell.disabled, "starter_produce_sellable_level_one")
	aura_before = int(state.economy["aura_balance"])
	await storage._trade("sell")
	check(int(state.experience["total_xp"]) == 26 and int(state.economy["aura_balance"]) == aura_before + 12, "produce_sale_aura_and_five_xp")
	storage.close()
	await settle()
	storage = open_storage("seeds")
	pick(storage, "wheat_seed")
	aura_before = int(state.economy["aura_balance"])
	price = int(storage._item("wheat_seed")["buy"])
	await storage._trade("buy")
	check(state.seed_inventory["wheat"] == 109 and int(state.economy["aura_balance"]) == aura_before - 6, "complete_loop_rebuys_seed")
	storage.close()
	await settle()
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
	# Marketplace screens against the real market routes. Bob's shop is stocked
	# by the fixture; alice stocks her own through the General Store.
	var bob_shop := int(api.data_of(await api.authenticated(HTTPClient.METHOD_POST, "/integration/market-fixture", {}))["shop_id"])
	await api.authenticated(HTTPClient.METHOD_POST, "/economy/earn", {"amount": 100})
	var my_shop: Dictionary = api.data_of(await api.authenticated(HTTPClient.METHOD_POST, "/market", {"option_id": "shop_option_02", "side": "right", "name": "Alice's Shop"}))
	await state.refresh_gameplay()
	var store: Node = load("res://Scripts/marketplace/general_store.gd").new()
	store.shop_id = int(my_shop["id"])
	stage.add_child(store)
	await wait_until(func() -> bool: return not store._catalog.is_empty(), "general_store_catalog_loads")
	check(store._grid.get_child_count() == store._catalog.size() and state.menu_open, "general_store_catalog_rendered")
	await shot("general_store_buy")
	var seeds_before := owned("wheat_seed")
	await store._buy("wheat_seed", 2)
	check(store._status.text == "Bought x2" and owned("wheat_seed") == seeds_before + 2, "general_store_buy_updates_inventory")
	await store._switch(store.STOCK)
	await store._put_on_shelf("corn", 2, 15)
	check(store._status.text == "Shelved x2 at 15 Aura" and owned("corn") == 0 and store._shelf.size() == 1 and int(store._shelf[0]["quantity"]) == 2 and int(store._shelf[0]["price"]) == 15, "general_store_stocks_own_shelf")
	await store._take_back("corn", 1)
	check(store._status.text == "Took x1 back" and owned("corn") == 1 and int(store._shelf[0]["quantity"]) == 1, "general_store_takes_stock_back")
	await shot("general_store_stock")
	store.close()
	await settle()
	check(not state.menu_open, "general_store_close_releases_menu")
	var own: Node = load("res://Scripts/marketplace/shop_window.gd").new()
	own.shop_id = int(my_shop["id"])
	own.shop_name = "Alice's Shop"
	own.is_mine = true
	stage.add_child(own)
	await wait_until(func() -> bool: return not own._listings.is_empty(), "own_shop_window_loads")
	check(own._title.text.contains("your shelf") and own._info.text == "Nothing sold yet." and not own._buy_button.visible, "own_shop_window_shows_shelf_and_sales")
	own.close()
	await settle()
	var shop: Node = load("res://Scripts/marketplace/shop_window.gd").new()
	shop.shop_id = bob_shop
	shop.shop_name = "Bob's Shop"
	stage.add_child(shop)
	await wait_until(func() -> bool: return not shop._listings.is_empty(), "friend_shop_window_loads")
	check(shop._listings.size() == 1 and int(shop._listings[0]["quantity"]) == 3 and int(shop._listings[0]["price"]) == 7, "friend_shop_window_lists_stock")
	shop._selected = "wheat"
	shop._qty = 4
	shop._render()
	check(shop._buy_button.disabled and shop._info.text.contains("Not that many left"), "friend_shop_blocks_overbuy")
	var aura_before_market := int(state.economy["aura_balance"])
	var wheat_before := owned("wheat")
	await shop._buy("wheat", 2)
	check(shop._status.text == "Bought x2" and owned("wheat") == wheat_before + 2 and int(state.economy["aura_balance"]) == aura_before_market - 14 and int(shop._listings[0]["quantity"]) == 1, "friend_shop_buy_moves_stock_and_aura")
	await shot("friend_shop")
	shop.close()
	await settle()
	# A full storage refuses one stack more than fits, but accepts what remains.
	await api.authenticated(HTTPClient.METHOD_POST, "/integration/fill-inventory", {})
	await state.refresh_gameplay()
	storage = open_storage("seeds")
	pick(storage, "wheat_seed", 4)
	aura_before = int(state.economy["aura_balance"])
	await storage._trade("buy")
	check(storage._status.text.contains("Inventory slots are full"), "store_full_capacity_rejects_new_stack")
	pick(storage, "wheat_seed", 3)
	await storage._trade("buy")
	check(int(state.inventory_summary["used_slots"]) == int(state.inventory_summary["capacity"]) and int(state.economy["aura_balance"]) == aura_before - 18, "partial_stack_purchase_confirmed_at_full_capacity")
	storage.close()
	await settle()
	var saved_inventory: String = JSON.stringify(state.inventory)
	var saved_aura := int(state.economy["aura_balance"])
	await api.logout()
	await settle()
	check(social._notices.is_empty() and social._private.is_empty() and social.message.text == "" and hud.active == "", "logout_private_state_cleared")
	response = await api.login("integration_alice", OS.get_environment("WANDERVILLE_TEST_PASSWORD"))
	login = api.data_of(response)
	session.set_session(login["access_token"], login["player"], login["refresh_token"])
	await state.load_from_backend()
	check(JSON.stringify(state.inventory) == saved_inventory and int(state.economy["aura_balance"]) == saved_aura, "relogin_restores_inventory_balance")
	await state.refresh_gameplay()
	var saved_file := FileAccess.open(output.path_join("restart.json"), FileAccess.WRITE)
	saved_file.store_string(JSON.stringify({"inventory": JSON.stringify(state.inventory), "aura": state.economy["aura_balance"]}))
	saved_file.close()
	print("HUD_RESULT failures=", failures)
	quit(0 if failures == 0 else 1)
