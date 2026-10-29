extends SceneTree


func _initialize() -> void:
	call_deferred("_check")


func _check() -> void:
	var title = load("res://Scenes/menus/TitleScreen.tscn").instantiate()
	root.add_child(title)
	current_scene = title
	await create_timer(0.5).timeout
	for viewport_size in [Vector2i(1578, 997), Vector2i(960, 600)]:
		root.size = viewport_size
		await create_timer(0.3).timeout
		for button in title.menu.get_children():
			if button.visible:
				assert(root.get_visible_rect().encloses(button.get_global_rect()))
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://../../test-output/title-%d.png" % viewport_size.x)
	print("TITLE_PREVIEW_OK")
	quit()
