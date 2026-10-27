extends SceneTree
## Render the actual shared SpriteFrames: six characters x eight directions.
## --headless runs the structural checks; a renderer also exports every pose.
const Frames := preload("res://Scripts/chara_frames.gd")
const Presentation := preload("res://Scripts/network/CharacterPresentation.gd")
const CAST := ["girl_a", "girl_b", "girl_c", "boy_a", "boy_b", "boy_c"]
var stage: Node2D
var view: SubViewport
var caption: Label
var actors: Array[AnimatedSprite2D] = []
var failures := 0
var slots := 0
var output := ""

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func text_label(value: String, where: Vector2, size: int = 16) -> Label:
	var label := Label.new()
	label.text = value
	label.position = where
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("f0e4cb"))
	stage.add_child(label)
	return label

func run() -> void:
	root.get_node("APIClient").base_url = "http://127.0.0.1:1/animation-review"
	output = OS.get_environment("TEST_ANIMATION_OUTPUT")
	if output.is_empty():
		output = "res://../../test-output/animation-foundation/godot"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	# A native window is clamped to the monitor's work area. Render to a fixed
	# viewport so the bottom directions are captured even on a laptop screen.
	view = SubViewport.new()
	view.size = Vector2i(1440, 1280)
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	stage = Node2D.new()
	view.add_child(stage)
	var background := ColorRect.new()
	background.color = Color("302922")
	background.size = Vector2(1440, 1280)
	stage.add_child(background)
	caption = text_label("Animation review", Vector2(24, 10), 24)
	text_label("Girl A is the reference. Ground guides mark the same cell anchor for every pose.", Vector2(24, 45))
	for column in CAST.size():
		text_label(CAST[column].replace("_", " ").capitalize(), Vector2(column * 240 + 70, 75), 20)
		for row in Frames.DIRECTIONS.size():
			var origin := Vector2(column * 240, 108 + row * 144)
			var guide := Line2D.new()
			guide.default_color = Color("a7bc83")
			guide.width = 1.0
			guide.points = PackedVector2Array([origin + Vector2(8, 124), origin + Vector2(232, 124)])
			stage.add_child(guide)
			text_label(Frames.DIRECTIONS[row].replace("_", " "), origin + Vector2(8, 0), 13)
			var actor := AnimatedSprite2D.new()
			actor.position = origin + Vector2(120, 124 - 97 * 0.62)
			actor.scale = Vector2.ONE * 0.62
			actor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			stage.add_child(actor)
			actors.append(actor)
	for action in Frames.ACTIONS:
		for column in CAST.size():
			var folder: String = root.get_node("Global").CHARACTERS[CAST[column]].folder
			var frames := Frames.preview_frames(folder, action)
			for row in Frames.DIRECTIONS.size():
				var name: String = action + "_" + Frames.DIRECTIONS[row]
				check(frames.has_animation(name) and frames.get_frame_count(name) == 6, CAST[column] + "/" + name)
				var actor := actors[column * 8 + row]
				actor.sprite_frames = frames
				actor.play(name)
				actor.pause()
				for pose in 6:
					var texture := frames.get_frame_texture(name, pose) as AtlasTexture
					check(texture != null and texture.region == Rect2(pose * 448, row * 448, 448, 448), "Fixed atlas cells")
					if action in ["idle", "walk", "run"]:
						var image := texture.get_image()
						check(opaque_bottom(image) == 321, CAST[column] + "/" + name + " grounded pose " + str(pose))
					slots += 1
		for pose in 6:
			caption.text = action.capitalize() + " - pose " + str(pose + 1) + " / 6"
			for actor in actors:
				actor.set_frame_and_progress(pose, 0.0)
			if DisplayServer.get_name() != "headless":
				await process_frame
				await RenderingServer.frame_post_draw
				view.get_texture().get_image().save_png(output.path_join(action + "-" + str(pose) + ".png"))
		# Check real playback advances through a full loop rather than just static
		# AtlasTexture regions; then pause before switching sheets.
		for actor in actors:
			actor.set_frame_and_progress(0, 0.0)
			actor.play()
		await create_timer(0.26).timeout
		for actor in actors:
			check(actor.frame > 0, "AnimatedSprite2D advances " + action)
			actor.pause()
	print("ANIMATION_VISUAL_REVIEW failures=", failures, " frame_slots=", slots, " action_direction_character_combinations=336")
	quit(failures)

func opaque_bottom(image: Image) -> int:
	for y in range(image.get_height() - 1, 0, -1):
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.5:
				return y + 1
	return 0
