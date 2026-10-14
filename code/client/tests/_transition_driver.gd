extends SceneTree

var _frames := 0

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var sm = root.get_node("SceneManager")
	var global = root.get_node("Global")
	var gs = root.get_node("GameState")
	root.get_node("APIClient").base_url = "http://127.0.0.1:1"

	global.token = "x"
	global.player_id = 1
	global.display_name = "Probe"
	gs.backend_ready = true
	gs.profile = {"character_code": "girl_a", "joined_at": "", "water_charges": 5, "display_name": "Probe"}
	gs.economy = {"taka_balance": 1}
	gs.experience = {"level": 1, "total_xp": 0}
	global.selected_character = "girl_a"
	global.selected_world_id = "campus"

	var d = Control.new()
	root.add_child(d)
	current_scene = d
	print("DRIVER start")

	sm.goto_profile()
	if not await _wait(5.0) or current_scene == null or current_scene.scene_file_path != "res://Scenes/menus/ProfileScene.tscn":
		print("DRIVER_STUCK profile transition")
		quit(1)
		return
	print("DRIVER profile loaded")

	sm.goto_post_login()
	if not await _wait(30.0):
		print("DRIVER_STUCK world transition")
		quit(1)
		return
	print("DRIVER world target=", current_scene.scene_file_path if current_scene != null else "null")
	quit(0)


func _wait(seconds: float) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(seconds * 1000.0):
		_frames += 1
		if _frames > 60000:
			return false
		await process_frame
	return true