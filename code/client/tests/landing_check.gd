extends SceneTree
## Isolated profile: title entry, saved-session routing and actual map/CDS render.
var failures := 0
var output := "res://../../test-output/landing"

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value: failures += 1; push_error(message)
func settle(seconds: float = 0.05) -> void:
	await create_timer(seconds).timeout
	await process_frame
func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))
func load_title() -> Control:
	var title: Control = load("res://Scenes/menus/TitleScreen.tscn").instantiate()
	root.add_child(title); current_scene = title
	return title

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(1920,1088)
	var api := root.get_node("APIClient")
	api.base_url = "http://127.0.0.1:1/landing-test"
	var session := root.get_node("Global")
	var state := root.get_node("GameState")
	session.clear_session()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://title_preferences.cfg"))
	var title := load_title(); await settle()
	check(title.find_child("OpeningSplash",true,false)==null and title.begin_button.has_focus(), "Startup shows the focused title menu immediately")
	check(not title.continue_button.visible, "New players have no Continue")
	var logo: TextureRect = title.canvas.get_node("Wordmark")
	check(logo.texture is AtlasTexture and logo.texture.atlas.get_image() != null and not logo.texture.atlas.get_image().is_empty(), "Landing uses the supplied logo with embedded image data")
	for card in [title.continue_button,title.begin_button,title.menu.get_node("WatchTrailer"),title.menu.get_node("SettingsButton")]:
		check(card._art.texture.atlas.get_image() != null and not card._art.texture.atlas.get_image().is_empty(), "Painted card contains exportable artwork: "+card.text)
	var trailer: Button = title.menu.get_node("WatchTrailer")
	check(not trailer.disabled and trailer.tooltip_text == "Trailer coming soon", "Trailer can be selected while its availability is clearly described")
	check(not title.begin_button._glyph.visible and not title.continue_button._glyph.visible and not title.canvas.get_node("AccountButton")._glyph.visible, "Journey and account cards have no extra icons")
	check(trailer._glyph.visible and title.menu.get_node("SettingsButton")._glyph.visible, "Trailer and settings retain their icons")
	var card_size := trailer.size
	var card_position := trailer.position
	trailer.mouse_entered.emit(); await settle(0.25)
	check(title._selected_card==title.begin_button and trailer._highlight<0.01, "Pointer hover does not change the wheel or keyboard selection")
	var wheel := InputEventMouseButton.new(); wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN; wheel.pressed=true
	Input.parse_input_event(wheel); await settle(0.09)
	check(trailer._highlight>0 and trailer._highlight<1, "Scrolling animates the selected option from beige to red")
	await shot("title-selection-transition"); await settle(0.18)
	check(title._selected_card==trailer and trailer._highlight>0.99 and title.begin_button._highlight<0.01, "Only the option reached by scrolling is red")
	check(trailer.size==card_size and trailer.position==card_position and trailer._art.texture==title.begin_button._art.texture, "Scrolling preserves the exact card shape, size and position")
	var cat_target: Vector2=title.menu.position+trailer.position+Vector2(trailer.size.x-116,-38)
	check(title._selection_cat.position.is_equal_approx(cat_target), "Pixel cat moves to the selected card")
	await shot("title-selected-trailer")
	title.begin_button.mouse_entered.emit(); await settle(0.25)
	check(title._selected_card==trailer and trailer._highlight>0.99, "Mouse hover cannot steal the selection after scrolling")
	Input.parse_input_event(wheel); await settle(0.25)
	check(title._selected_card==title.menu.get_node("SettingsButton"), "Mouse wheel moves selection to Settings")
	var up := InputEventAction.new(); up.action="ui_up"; up.pressed=true
	Input.parse_input_event(up); await settle(0.25)
	check(title._selected_card==trailer, "Keyboard navigation selects and highlights Watch Trailer")
	check(trailer._highlight>0.99 and title.menu.get_node("SettingsButton")._highlight<0.01, "Arrow navigation restores the previous option to beige")
	trailer.pressed.emit(); await settle()
	check(is_instance_valid(title.popup), "Unconfigured trailer opens a coming-soon message")
	title._close_popup(); await settle(0.25)
	check(is_equal_approx(title.menu.position.x+title.menu.size.x/2,title.DESIGN.x/2), "Reference card stack is centered")
	check(not title.background_player.visible and root.get_node("SceneManager").journey_backdrop.village.texture != null, "No video uses original village fallback")
	await shot("title-new-player")
	title.begin_button.pressed.emit(); await settle(0.65)
	check(current_scene.scene_file_path == "res://Scenes/menus/LoginScene.tscn", "Begin Adventure reaches existing authentication directly")
	await shot("begin-adventure")
	current_scene.queue_free(); await settle()
	session.token = "isolated-saved-session"; session.player_id = 999
	session.selected_character = "girl_a"; session.selected_world_id = "campus"
	session.save_session(); session.token = ""; session.player_id = 0
	title = load_title(); await settle()
	check(title.find_child("OpeningSplash",true,false)==null and title.continue_button.visible, "Returning save restores Continue directly on the title menu")
	await shot("title-returning-player")
	var audio := root.get_node("AudioManager")
	var volume: float = audio.music_volume
	var muted: bool = audio.music_muted
	title.music_button.pressed.emit()
	check(audio.music_muted != muted and audio.music_volume == volume, "Music toggle preserves the chosen volume")
	check(title.music_button.text.is_empty() and title.music_button.tooltip_text == ("Unmute music" if audio.music_muted else "Mute music"), "Speaker icon has no written label and describes its action")
	await shot("title-muted")
	title.music_button.pressed.emit()
	title._open_settings(); await settle(0.4)
	check(title.settings.visible and title.settings.scene_file_path.ends_with("SettingsOverlay.tscn"), "Title uses gameplay settings")
	title.begin_button.pressed.emit(); title.continue_button.pressed.emit()
	check(title.popup == null and not title._busy, "Settings blocks underlying journey actions")
	await shot("title-settings")
	# Avoid a profile-save request in this isolated presentation check.
	title.settings.hide()
	title.continue_button.pressed.emit()
	var deadline := Time.get_ticks_msec() + 20000
	while title._busy and Time.get_ticks_msec() < deadline: await settle(0.1)
	check(not title._busy and not title.continue_button.disabled, "Network failure enables Continue retry")
	check(session.token == "isolated-saved-session" and title.status.visible, "Offline Continue preserves the save and shows the failure")
	root.size = Vector2i(960,640); title._fit(); await settle()
	check(Rect2(Vector2.ZERO,root.get_visible_rect().size).encloses(title.menu.get_global_transform() * Rect2(Vector2.ZERO,title.menu.size)), "Menu fits a small window")
	await shot("title-compact")
	title._credits(); await settle()
	check(is_instance_valid(title.popup), "Credits opens")
	title._close_popup()
	title.queue_free(); await settle(); current_scene = null
	root.size = Vector2i(1920,1088)
	session.clear_session(); session.selected_character = "girl_a"
	state.menu_open = false; state.social_open = false
	# Known pre-existing map TileSet warnings are captured in the log as usual.
	var world: Node2D = load("res://Scenes/world.tscn").instantiate()
	root.add_child(world); current_scene = world
	await settle(0.6)
	check(world.get_node("Map").scene_file_path == "res://Scenes/map2.tscn", "Original map remains in the actual game")
	check(world.find_child("InventoryButton",true,false) == null, "HUD has no duplicate inventory")
	await shot("actual-world")
	var storage: Node
	for child in world.get_children():
		if child.get_script() == load("res://Scripts/inventory/storage_house.gd"): storage = child
	check(storage != null and not storage._tile_buildings.is_empty(), "CDS tiles own inventory access")
	if storage != null and not storage._tile_buildings.is_empty():
		var camera: Camera2D = world.get_node("girl/Camera2D")
		world.get_node("girl").set_physics_process(false)
		var footprint: CollisionPolygon2D = world.find_child("Collision_cds",true,false)
		var bounds := Rect2(footprint.polygon[0],Vector2.ZERO)
		for point in footprint.polygon: bounds = bounds.expand(point)
		var target := footprint.to_global(bounds.get_center())
		check(storage.contains_world_point(target) and not storage.contains_world_point(Vector2(999999,999999)), "CDS hit testing follows the painted building under map transforms")
		camera.global_position = target
		camera.reset_smoothing(); camera.force_update_scroll(); await settle()
		await shot("cds-building")
		var click := InputEventMouseButton.new(); click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true
		click.position = storage.get_canvas_transform() * target
		storage._unhandled_input(click); await settle()
		check(is_instance_valid(storage._menu) and state.menu_open, "CDS opens the existing inventory room")
		await shot("cds-inventory")
	world.queue_free(); current_scene = null; await settle()
	# The existing house-owner hint starts a four-second autoload timer.
	# Let that transient flash finish before the test process shuts down.
	await settle(4.1)
	var cleanup_deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < cleanup_deadline:
		var pending := false
		for child in api.get_children():
			if child is HTTPRequest: pending = true
		if not pending: break
		await settle(0.1)
	print("LANDING_CHECK failures=",failures)
	quit(failures)
