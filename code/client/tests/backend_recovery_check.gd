extends SceneTree

var failures := 0

class Collector extends Node2D:
	var _busy := false
	var fishing := false


func _initialize() -> void:
	call_deferred("_check")


func check(value: bool, message: String) -> void:
	print("RECOVERY_CHECK ", message, " PASS" if value else " FAIL")
	if not value:
		failures += 1


func _check() -> void:
	var state = root.get_node("GameState")
	var session = root.get_node("Global")
	var api = root.get_node("APIClient")
	session.clear_session()
	api.set_script(load("res://tests/fixtures/backend_recovery_api.gd"))
	api.realtime = load("res://autoloads/RealtimeClient.gd").new()
	api.add_child(api.realtime)
	state.set_process(false)
	var world := Node2D.new()
	world.scene_file_path = root.get_node("SceneManager").WORLD_SCENE
	root.add_child(world)
	current_scene = world
	session.token = "isolated-recovery-fixture"
	session.player_id = 99999
	for path in ["/profile", "/world/me", "/economy/", "/inventory/", "/world/state", "/farm/plots", "/economy/xp", "/farm/visiting/session"]:
		state.reset()
		api.fail_path = path
		check(not await state.load_from_backend(), "failed startup remains blocked: " + path)
		check(path in state.last_error and not state._loading, "failure identifies endpoint and releases loading flag")
		api.fail_path = ""
		state._process(3.1)
		var recovered: bool = await state.data_loaded
		check(recovered and state.backend_ready and state.water_drops == 7 and state.last_error.is_empty(), "automatic retry restores authoritative state")
	state.reset()
	await state.refresh_gameplay()
	check(state.backend_ready, "manual refresh repairs an incomplete initial load")
	state.reset()
	var pond = load("res://Scripts/water_source.gd").new()
	world.add_child(pond)
	pond.set_physics_process(false)
	var collector := Collector.new()
	world.add_child(collector)
	pond._collector = collector
	pond.player_in_range = true
	var refill := InputEventAction.new()
	refill.action = "collect_water"
	refill.pressed = true
	pond._input(refill)
	check("Reconnecting" in root.get_node("HousePrompt").text() and state._loading,
		"Q explains missing data and starts recovery without sending a mutation")
	await state.data_loaded
	check(state.backend_ready and not pond._refilling, "Q recovery leaves refill usable")
	session.clear_session()
	state._process(4.0)
	check(not state._loading and not state.backend_ready, "signed-out state never starts recovery")
	quit(1 if failures else 0)
