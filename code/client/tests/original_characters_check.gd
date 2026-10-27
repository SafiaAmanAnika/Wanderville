extends SceneTree
const Frames := preload("res://Scripts/chara_frames.gd")
var failures := 0
const Presentation := preload("res://Scripts/network/CharacterPresentation.gd")
const Protocol := preload("res://Scripts/network/MovementProtocol.gd")
var checked := 0
var output := ""

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value: failures += 1; push_error(message)

func run() -> void:
	output = OS.get_environment("TEST_LOBBY_OUTPUT")
	if output.is_empty(): output = "user://original-characters"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var session := root.get_node("Global")
	root.get_node("APIClient").base_url = "http://127.0.0.1:1/original-characters-test"
	session.token = ""; session.selected_world_id = "retained-world"
	session.modular_look = {"enabled":true,"preset":"female_a","skin":4}
	var retained: Dictionary = session.modular_look.duplicate(true)
	for code in session.CHARACTERS:
		var folder: String = session.CHARACTERS[code].folder
		if folder == "": continue
		var body: CharacterBody2D = session.get_character_scene(code).instantiate()
		body.require_world_connection = false; root.add_child(body); body.set_physics_process(false)
		check(body.anim.visible and not body.has_node("Appearance"), code + ": original sprite, no generated overlay")
		check(body.scale == Frames.GAMEPLAY_SCALE, "Original scene uses the shared uniform gameplay scale")
		for slot in 8:
			var direction: Vector2 = Presentation.direction_for_facing(slot)
			check(Protocol.facing_from_direction(direction) == slot, "Facing vector round trip")
			Presentation.play(body, true, direction, slot)
			check(body.anim.animation == "run_" + Presentation.DIRECTION_NAMES[slot], "Movement facing matches animation")
			Presentation.play(body, false, Vector2.ZERO, slot)
			check(body.anim.animation == "idle_" + Presentation.DIRECTION_NAMES[slot], "Stopping preserves facing")
		check(body.SPEED == 300.0, "Existing movement speed stays 300")
		for action in Frames.ACTIONS:
			var frames := Frames.preview_frames(folder, action)
			for row in 8:
				var name: String = action + "_" + Frames.DIRECTIONS[row]
				check(frames.has_animation(name) and frames.get_frame_count(name) == 6, code + "/" + name + ": original six frames")
				for frame in 6:
					var texture := frames.get_frame_texture(name, frame) as AtlasTexture
					check(texture != null and texture.atlas.resource_path == folder + "/" + Frames.FILES[action], "Frame uses original source artwork")
					var expected := Rect2(frame * 448, row * 448, 448, 448)
					check(texture.region == expected, "Fixed cells preserve exported ground anchors without sampling adjacent frames")
					checked += 1
		for action in ["walk", "run"]:
			for direction in Frames.DIRECTIONS:
				body._play_if_new(action + "_front")
				body.anim.set_frame_and_progress(3, 0.42)
				body._play_if_new(action + "_" + direction)
				check(body.anim.frame == 3 and is_equal_approx(body.anim.frame_progress, 0.42), "Turning keeps the stride phase")
				check(body.anim.sprite_frames.get_animation_loop(action + "_" + direction), "Locomotion loops")
				check(body.anim.sprite_frames.get_animation_speed(action + "_" + direction) == (6.0 if action == "walk" else 10.0), "Walk/Run rate")
		body.anim.stop(); body._play_if_new("run_" + body.facing)
		check(body.anim.is_playing(), "A stopped movement clip resumes")
		body.play_action("scythe")
		await create_timer(0.85).timeout
		check(not body._busy and String(body.anim.animation).begins_with("idle_"), "Existing action completes and restores idle")
		body.queue_free(); await process_frame
	check(session.modular_look == retained, "Old appearance preferences never rewrite the saved character")
	var unavailable := "unavailable-saved-character"
	session.selected_character = unavailable
	check(session.get_character_scene(unavailable).resource_path.ends_with("player1.tscn") and session.selected_character == unavailable, "Unavailable saved character falls back without rewriting its ID")
	var preview_script: Script = load("res://Scripts/customization/character_preview.gd")
	if DisplayServer.get_name() != "headless": await render_cast(preview_script, session)
	session.selected_character = "boy_c"
	change_scene_to_file("res://Scenes/CustomizationLobby.tscn"); await create_timer(0.25).timeout
	var room: Node2D = current_scene
	var host: Node = room.get_node("CustomizationInteractions")
	var original: CharacterBody2D = room.player
	var spot := original.global_position
	host._activate(&"character")
	var panel: PanelContainer = host._creator
	check(panel.options.get_child_count() == 6, "Only the original six are offered")
	panel.avatar.pause()
	panel.avatar.set_frame_and_progress(3, 0.42)
	for turn in 8:
		panel._turn_preview(1)
		check(panel.avatar.direction == Frames.DIRECTIONS[(turn + 1) % 8], "Preview rotates through each exported direction")
		check(not panel.avatar.is_playing() and panel.avatar.frame == 3 and is_equal_approx(panel.avatar.frame_progress, 0.42), "Turning preserves paused pose and stride phase")
	for action in Frames.ACTIONS:
		panel._set_preview_pose(action, "front")
		check(panel.avatar.animation == action + "_front" and not panel.avatar.is_playing(), "Every action can be inspected while paused")
	panel.find_child("PreviewFrameStep", true, false).pressed.emit()
	check(panel.avatar.frame == 4 and not panel.avatar.is_playing(), "Frame step advances exactly one pose")
	panel.find_child("PreviewPlayback", true, false).pressed.emit()
	check(panel.avatar.is_playing(), "Playback control resumes animation")
	panel.avatar.pause()
	panel.options.get_child(1).pressed.emit()
	check(not panel.avatar.is_playing() and panel.avatar.frame == 4, "Changing character preserves a paused inspection pose")
	check(panel.draft == "girl_b" and session.selected_character == "boy_c" and room.player == original, "Preview does not swap the player")
	host.close()
	check(session.selected_character == "boy_c" and session.modular_look == retained, "Closing discards unsaved selection")
	host._activate(&"character"); panel.options.get_child(1).pressed.emit()
	await panel.save(); await process_frame
	check(session.selected_character == "girl_b" and session.modular_look.is_empty(), "Explicit Save selects original artwork")
	check(room.player != original and room.player.global_position == spot and get_nodes_in_group("player").size() == 1, "Explicit swap preserves position and one player")
	check(session.selected_world_id == "retained-world", "Character change preserves world state")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png(output.path_join("original-picker.png"))
	host.close()
	check(not root.get_node("GameState").menu_open, "Closing resumes movement")
	change_scene_to_file("res://Scenes/SocialLobby.tscn"); await create_timer(0.25).timeout
	var npc := current_scene.get_node("Receptionist") as AnimatedSprite2D
	check(npc != null and npc.get_script() == null, "Receptionist is an animated sprite without player controls")
	check(npc.animation == &"idle_front" and npc.is_playing() and npc.sprite_frames.get_animation_loop("idle_front"), "Receptionist loops front idle")
	check(npc.sprite_frames.get_frame_count("idle_front") == 6 and npc.sprite_frames.get_animation_speed("idle_front") == 6.0, "Receptionist uses original six-frame idle at 6 FPS")
	var tex := npc.sprite_frames.get_frame_texture("idle_front", 0) as AtlasTexture
	check(tex.atlas.resource_path == "res://Assets/charas/CharacterC/idle.png", "Receptionist matches original Girl C artwork")
	var pose: int = npc.frame; var position := npc.position
	await create_timer(0.3).timeout
	check(npc.frame != pose and npc.position == position, "Idle advances while NPC remains stationary")
	check(get_nodes_in_group("player").size() == 1, "Receptionist is never a duplicate player")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png(output.path_join("social-receptionist.png"))
	print("ORIGINAL_CHARACTERS_CHECK failures=", failures, " original_frame_slots=", checked)
	quit(failures)

func render_cast(script: Script, session: Node) -> void:
	var view := SubViewport.new(); view.size = Vector2i(1200, 1040); view.transparent_bg = true; view.world_2d = World2D.new(); view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(view)
	var column := 0
	for code in session.CHARACTERS:
		if session.CHARACTERS[code].folder == "": continue
		for row in 4:
			var preview: AnimatedSprite2D = script.new(); preview.character = code; view.add_child(preview)
			preview.position = Vector2(100 + column * 200, 120 + row * 260); preview.scale = Vector2.ONE * 0.85
			preview.set_pose("walk" if row < 2 else "run", "right" if row % 2 == 0 else "left", column % 6)
		column += 1
	await create_timer(0.2).timeout; await RenderingServer.frame_post_draw
	view.get_texture().get_image().save_png(output.path_join("six-original-walk-run.png"))
	view.queue_free(); await process_frame
