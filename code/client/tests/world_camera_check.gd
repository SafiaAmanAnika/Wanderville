extends SceneTree
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	print("CAMERA_CHECK ", label, " ", "PASS" if ok else "FAIL")
	if not ok: failures += 1

func run() -> void:
	var stage := Node2D.new()
	root.add_child(stage)
	current_scene = stage
	var player := Node2D.new()
	stage.add_child(player)
	var camera := Camera2D.new()
	camera.set_script(load("res://Scripts/world_camera.gd"))
	player.add_child(camera)
	camera.make_current()
	await process_frame
	check(camera.zoom.x >= 0.449, "starts_zoomed_in")
	for size in [Vector2i(800,600), Vector2i(1920,1080), Vector2i(3440,1440), Vector2i(800,1600)]:
		root.size = size
		await process_frame
		for point in [Vector2(-3399,-2952), Vector2(4401,-2922), Vector2(4401,2373), Vector2(-3384,2373)]:
			player.global_position = point
			camera.force_update_scroll()
			await process_frame
			var center: Vector2 = camera.get_screen_center_position()
			var half: Vector2 = root.get_visible_rect().size / camera.zoom / 2.0
			var visible := Rect2(center-half, half*2)
			check(camera.view_bounds.grow(1).encloses(visible), "viewport_inside_fence_"+str(size)+"_"+str(point))
	print("CAMERA_RESULT failures=", failures)
	quit(failures)
