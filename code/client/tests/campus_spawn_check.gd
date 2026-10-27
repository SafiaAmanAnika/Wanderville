extends SceneTree
const Layout := preload("res://Scripts/network/CampusLayout.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	print("CAMPUS_CHECK ", label, " ", "PASS" if ok else "FAIL")
	if not ok:
		failures += 1

func run() -> void:
	var api := root.get_node("APIClient")
	api.base_url = "http://127.0.0.1:1"
	var session := root.get_node("Global")
	session.token = ""
	session.player_id = 0
	session.selected_character = "girl_a"
	var world: Node2D = load("res://Scenes/world.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	await physics_frame
	await physics_frame
	var body := world.get_node("girl") as CharacterBody2D
	check(body.global_position.is_equal_approx(Layout.spawn()), "scene_matches_authoritative_spawn")
	check(Layout.walkable(body.global_position), "spawn_inside_fence_on_clear_ground")
	check(world.get_node("Map").scale == Vector2(15, 15), "map_scale_preserved")
	check(CampusCollision.live_version(world.get_node("Map")) == CampusCollision.shape_version(CampusCollision.extract_shapes()), "dedicated_server_uses_same_collision")
	check(CampusCollision.CAMPUS_SPAWN == Layout.spawn(), "dedicated_server_uses_same_spawn")
	var query := PhysicsShapeQueryParameters2D.new()
	var clearance := CircleShape2D.new()
	clearance.radius = 60.0
	query.shape = clearance
	query.transform = Transform2D(0.0, body.global_position)
	query.collision_mask = 1
	query.exclude = [body.get_rid()]
	check(world.get_world_2d().direct_space_state.intersect_shape(query).is_empty(), "spawn_has_physics_clearance")
	var water := world.get_node("Map/WaterSource/WaterInteraction") as Area2D
	check(water.get_script() != null and water.get_children().any(func(child: Node) -> bool: return child is CollisionPolygon2D), "pond_interaction_initializes")
	# The selectable-character controller must keep moving across a socket blip.
	var selected: CharacterBody2D = load("res://Scenes/charagirlA.tscn").instantiate()
	selected.require_world_connection = true
	selected.use_saved_appearance = false
	world.add_child(selected)
	selected.global_position = Layout.spawn()
	await physics_frame
	session.token = "isolated-spawn-check"
	session.player_id = 918273
	api.realtime.connected = false
	var before := selected.global_position
	Input.action_press("ui_right")
	await physics_frame
	await physics_frame
	Input.action_release("ui_right")
	check(selected.global_position.x > before.x, "selectable_character_moves_during_disconnect")
	session.token = ""
	session.player_id = 0
	selected.queue_free()
	if OS.get_environment("CAMPUS_CAPTURE") != "":
		root.size = Vector2i(1200, 900)
		var camera := body.get_node("Camera2D") as Camera2D
		camera.position = Vector2.ZERO
		camera.zoom = Vector2(0.16, 0.16)
		camera.make_current()
		camera.reset_smoothing()
		camera.force_update_scroll()
		await physics_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("CAMPUS_CAPTURE"))
	print("CAMPUS_RESULT failures=", failures)
	quit(failures)
