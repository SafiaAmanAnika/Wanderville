extends SceneTree


func _initialize() -> void:
	call_deferred("_check")


func _check() -> void:
	var map := load("res://Scenes/map2.tscn").instantiate() as Node2D
	map.position = Vector2(246, -252)
	map.scale = Vector2(15, 15)
	root.add_child(map)
	# Authored lamp coordinates are map-local, not tile-layer-local.
	var lamps := map.get_node("Lampposts")
	var failures := 0
	var checked := 0
	for child in lamps.get_children():
		if child is Sprite2D:
			checked += 1
			var expected := map.to_global(child.position)
			if child.global_position.distance_to(expected) > 0.01:
				printerr("Lamp does not inherit campus transform: ", child.name,
					" actual=", child.global_position, " expected=", expected)
				failures += 1
			if child.texture == null or not child.is_visible_in_tree():
				failures += 1
	if checked != 12:
		failures += 1
	print("LAMP_CHECK checked=", checked, " failures=", failures)
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1280, 827)
		var camera := Camera2D.new()
		root.add_child(camera)
		camera.position = map.to_global(Vector2(50, -40))
		camera.zoom = Vector2(0.16, 0.16)
		await create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../../test-output/lamppost-layout.png")
	map.queue_free()
	quit(1 if failures else 0)
