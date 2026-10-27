extends SceneTree
## Exercise the real reference controller with input, movement, turns and stops.
const Presentation := preload("res://Scripts/network/CharacterPresentation.gd")
var failures := 0
var view: SubViewport
var output := "res://../../test-output/animation-foundation/godot"

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	root.get_node("APIClient").base_url = "http://127.0.0.1:1/reference-motion"
	root.get_node("GameState").menu_open = false
	root.get_node("GameState").social_open = false
	view = SubViewport.new()
	view.size = Vector2i(800, 720)
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var background := ColorRect.new()
	background.size = Vector2(800, 720)
	background.color = Color("50634c")
	view.add_child(background)
	for y in range(0, 720, 40):
		var line := Line2D.new()
		line.default_color = Color("61745b")
		line.width = 1.0
		line.points = PackedVector2Array([Vector2(0, y), Vector2(800, y)])
		view.add_child(line)
	var caption := Label.new()
	caption.position = Vector2(24, 20)
	caption.add_theme_font_size_override("font_size", 22)
	view.add_child(caption)
	var body: CharacterBody2D = load("res://Scenes/charagirlA.tscn").instantiate()
	body.require_world_connection = false
	body.position = Vector2(360, 260)
	view.add_child(body)
	for slot in 8:
		var direction: Vector2 = Presentation.direction_for_facing(slot)
		var before := body.position
		set_input(direction)
		await create_timer(0.21).timeout
		var moved := body.position - before
		check(moved.length() > 40.0 and moved.normalized().dot(direction) > 0.99, "Controller moves in facing " + str(slot))
		check(body.anim.animation == "run_" + Presentation.DIRECTION_NAMES[slot], "Movement animation follows input")
		caption.text = "Girl A reference / moving / " + Presentation.DIRECTION_NAMES[slot]
		await capture("reference-" + str(slot) + "-run.png")
		set_input(Vector2.ZERO)
		await physics_frame
		await physics_frame
		check(body.anim.animation == "idle_" + Presentation.DIRECTION_NAMES[slot], "Releasing input keeps the last facing")
		var stopped := body.position
		await create_timer(0.12).timeout
		check(body.position.is_equal_approx(stopped), "Idle has no body-position drift")
		caption.text = "Girl A reference / standing / " + Presentation.DIRECTION_NAMES[slot]
		await capture("reference-" + str(slot) + "-idle.png")
	set_input(Vector2.ZERO)
	print("REFERENCE_MOTION_CHECK failures=", failures, " directions=8 moving_and_stopped_pairs=8")
	quit(failures)

func set_input(direction: Vector2) -> void:
	for action in ["ui_left", "ui_right", "ui_up", "ui_down"]:
		Input.action_release(action)
	if direction.x > 0.0: Input.action_press("ui_right")
	if direction.x < 0.0: Input.action_press("ui_left")
	if direction.y > 0.0: Input.action_press("ui_down")
	if direction.y < 0.0: Input.action_press("ui_up")

func capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	view.get_texture().get_image().save_png(output.path_join(filename))
