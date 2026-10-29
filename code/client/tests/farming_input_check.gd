extends SceneTree
## Run with an isolated APPDATA profile; exercises the real world and GUI input.

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	print("FARM_INPUT_CHECK ", message, " PASS" if value else " FAIL")
	if not value: failures += 1

func click_tile(farm: Node, tile: Vector2i) -> void:
	# A committed farm action plays a tool animation; subsequent clicks wait
	# for that animation just as a player must, rather than racing two frames.
	var player := current_scene.get_node("girl")
	var deadline := Time.get_ticks_msec() + 6000
	while player.get("_busy") == true and Time.get_ticks_msec() < deadline:
		await process_frame
	var click := InputEventMouseButton.new()
	click.position = root.get_canvas_transform() * farm._tile_to_world(tile)
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	root.push_input(click, true)
	click = click.duplicate()
	click.pressed = false
	root.push_input(click, true)
	await process_frame
	await process_frame

func run() -> void:
	root.size = Vector2i(1578, 997)
	var session := root.get_node("Global")
	session.clear_session()
	session.selected_character = "girl_a"
	var state := root.get_node("GameState")
	root.get_node("APIClient").base_url = "http://127.0.0.1:1/farming-input-check"
	var world: Node = load("res://Scenes/world.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	await create_timer(4.0 if DisplayServer.get_name() != "headless" else 0.5).timeout
	var farm: Node = world.get_node("FarmController")
	var player: CharacterBody2D = world.get_node("girl")
	player.set_physics_process(false)
	var zone: Area2D = world.get_node("Map/FarmField/FarmZone")
	var shape: CollisionShape2D = zone.get_node("CollisionShape2D")
	var area := Rect2(shape.global_position - shape.shape.size * shape.global_scale / 2.0,
		shape.shape.size * shape.global_scale)
	check(farm.farm_layer != null, "farm layer resolves in the active map")
	check(area.encloses(Rect2(farm.FARM_AREA_MIN, farm.FARM_AREA_MAX-farm.FARM_AREA_MIN)), "all farm cells fit the interaction zone")
	check(Rect2(farm.FARM_AREA_MIN, farm.FARM_AREA_MAX-farm.FARM_AREA_MIN).is_equal_approx(area), "the whole grass rectangle is farmable with no side strips")
	for edge in [area.position+Vector2.ONE, area.end-Vector2.ONE,
		Vector2(area.position.x+1,area.end.y-1), Vector2(area.end.x-1,area.position.y+1)]:
		check(farm._is_in_farm_area(farm._get_tile_pos(edge)), "field edge %s maps to a valid farm cell" % edge)
	player.global_position = farm._tile_to_world(Vector2i(8,10))
	var camera: Camera2D = player.get_node("Camera2D")
	camera.position_smoothing_enabled = false
	camera.reset_smoothing()
	await create_timer(0.2).timeout
	check(farm._player_in_zone, "player entering the field enables farming")
	var motion := InputEventMouseMotion.new()
	motion.position = root.get_canvas_transform() * farm._tile_to_world(Vector2i(8,10))
	root.push_input(motion, true)
	await process_frame
	await process_frame
	check(farm._cursor.visible and farm._hover_tile() == Vector2i(8,10), "moving the mouse shows the tile outline before clicking")
	await click_tile(farm, Vector2i(8,10))
	check(farm.tilled_tiles.has("8,10"), "viewport click tills a reachable tile")
	check(farm._hover_tile() == Vector2i(8,10), "hover and click resolve the same viewport position")
	check(farm._cursor.visible and farm._cursor.global_position.is_equal_approx(farm._tile_to_world(Vector2i(8,10))), "tile outline appears at the clicked cell")
	await click_tile(farm, Vector2i(9,10))
	var soil: Sprite2D = farm.get_node("Soil_9,10")
	check(soil.texture.get_image().get_used_rect().intersects(Rect2i(soil.region_rect)), "soil crop contains visible artwork")
	var soil_size: Vector2=soil.region_rect.size*soil.scale
	check(soil_size.is_equal_approx(farm._drawn_size()),"soil fills the configured grid cell with the intended gap")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../../test-output/farming-input/rendered-till.png")
	await click_tile(farm, Vector2i(8,10))
	check(farm.seed_picker.visible, "second click opens seed selection")
	var seeds: Array = farm.seed_picker.grid.get_children()
	var wheat: Button
	for button in seeds:
		if button.get_meta("item_code", "") == "wheat_seed": wheat = button
	check(wheat != null and not wheat.disabled, "owned starter wheat seed is plantable offline")
	if wheat != null and not wheat.disabled:
		var before: int = state.seed_inventory.get("wheat", 0)
		wheat.pressed.emit()
		await process_frame
		check(farm.active_crops.has("8,10") and not farm.seed_picker.visible, "seed choice plants the actual crop and closes the picker")
		check(state.seed_inventory.get("wheat",0) == before-1, "planting consumes one owned seed")
		state._rebuild_seed_inventory()
		check(state.seed_inventory.get("wheat",0) == before-1, "inventory refresh does not restore a consumed seed")
		state.water_drops = 3
		await click_tile(farm, Vector2i(8,10))
		check(farm.active_crops["8,10"].watered and state.water_drops == 2, "click waters the crop and spends one water charge")
		var visual: AnimatedSprite2D = farm.get_node("CropVisual_8,10/AnimatedSprite2D")
		visual.frame_durations.assign([0.01, 0.01, 0.01, 0.01])
		await create_timer(0.3).timeout
		check(farm.active_crops["8,10"].stage == farm.GROWTH_STAGES, "watered crop reaches harvest readiness")
		await click_tile(farm, Vector2i(8,10))
		check(not farm.active_crops.has("8,10") and not farm.tilled_tiles.has("8,10"), "click harvests the ripe crop and clears the soil")
		var harvested := false
		for row in state.inventory:
			if row.item_code == "wheat" and int(row.quantity) > 0: harvested = true
		check(harvested, "harvested crop reaches the inventory")
	else:
		farm.seed_picker.hide_menu()
	for tile in [Vector2i(0,0), Vector2i(16,0), Vector2i(0,20), Vector2i(16,20)]:
		player.global_position = farm._tile_to_world(tile)
		camera.reset_smoothing()
		await create_timer(0.1).timeout
		check(farm._player_in_zone, "outer farm cell %s is reachable inside the zone" % tile)
		await click_tile(farm, tile)
		check(farm.tilled_tiles.has(farm._key(tile)), "viewport click tills outer farm cell %s" % tile)
	var outline: PackedVector2Array=farm.get_node("HoverCursor").points
	check(Vector2(outline[1].x*2,-outline[1].y*2).is_equal_approx(farm.tile_visual_size), "hover outline matches the configured grid cell")
	# Offline fallback must never invent planting eligibility for an account.
	session.token = "farming-input-fixture"
	session.player_id = 99999
	farm.seed_picker.show_menu()
	for button in farm.seed_picker.grid.get_children():
		if button.get_meta("item_code", "") == "wheat_seed":
			check(button.disabled, "signed-in seeds still require server harvest metadata")
	farm.seed_picker.hide_menu()
	state.backend_ready = false
	check(farm._blocked(), "signed-in farming waits for authoritative state")
	await click_tile(farm, Vector2i(16,20))
	check("has not loaded" in root.get_node("HousePrompt")._label.text, "unloaded farm explains why a click was rejected")
	state.backend_ready = true
	check(not farm._blocked(), "signed-in farming enables after state loads")
	state.social_open = true
	check(farm._blocked(), "open social UI blocks farm input")
	state.social_open = false
	session.token = ""
	session.player_id = 0
	player.global_position = farm.FARM_AREA_MAX + Vector2(100,100)
	await create_timer(0.15).timeout
	await click_tile(farm, Vector2i(16,20))
	check("Step into" in root.get_node("HousePrompt")._label.text, "clicking from outside the field explains where to stand")
	world.queue_free()
	await process_frame
	quit(1 if failures else 0)
