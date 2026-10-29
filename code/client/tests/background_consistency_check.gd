extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1578, 997)
	root.get_node("Global").clear_session()
	var expected = load("res://Assets/background/bg.webp")
	for file in ["email_verification", "forgot_password", "login_scene", "map_selection_screen", "map_showcase_screen", "profile_scene", "reset_password", "settings_overlay", "signup_scene"]:
		var script = load("res://Scripts/menus/%s.gd" % file)
		assert(script.get_script_constant_map()["BG_TEXTURE"] == expected, file)
	var manager = root.get_node("SceneManager")
	var title = load(manager.TITLE_SCENE).instantiate()
	root.add_child(title)
	current_scene = title
	await create_timer(0.2).timeout
	manager.show_loading()
	await create_timer(0.2).timeout
	assert(manager.journey_backdrop.village.texture == expected)
	assert(manager._loading_screen.background.texture == expected)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://Assets/ui/loading_boot.png")
	manager.hide_loading()
	title.queue_free()
	await process_frame
	var login = load(manager.LOGIN_SCENE).instantiate()
	root.add_child(login)
	current_scene = login
	await create_timer(0.2).timeout
	assert(manager.journey_backdrop.village.texture == expected)
	print("BACKGROUND_CONSISTENCY_OK: title, loading and account screens use bg.webp")
	quit()
