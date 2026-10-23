extends SceneTree
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	print("CAMPUS_ENTRANCE ", message, " ", value)
	if not value: failures += 1
func settled(path: String) -> bool:
	var end := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < end:
		if current_scene != null and current_scene.scene_file_path == path and not root.get_node("SceneManager")._is_transitioning: return true
		await create_timer(0.05).timeout
	return false
func run() -> void:
	var session := root.get_node("Global")
	session.token = ""; session.selected_character = "girl_a"
	root.get_node("APIClient").base_url = "http://127.0.0.1:1/entrance-test"
	var manager := root.get_node("SceneManager")
	change_scene_to_file("res://Scenes/world.tscn")
	await process_frame; await physics_frame
	for destination in ["social", "customization"]:
		var entrance: Node = null
		for child in current_scene.get_children():
			if child.has_method("destination_at"): entrance = child; break
		check(entrance != null, "world installs building interactions")
		if entrance == null: quit(1); return
		check(entrance._tile_buildings.size() == 2, "both painted halls discovered")
		var matched := false
		for building in entrance._tile_buildings:
			var layer: TileMapLayer = building.layer
			for cell in layer.get_used_cells_by_id(building.source_id):
				check(entrance.destination_at(layer.to_global(layer.map_to_local(cell))) == building.destination, "painted cell routes correctly")
			if building.destination == destination: matched = true
		check(matched, destination + " destination exists")
		check(entrance.destination_at(Vector2(-999999,-999999)).is_empty(), "empty map area has no entrance")
		var outdoor: Vector2 = current_scene.get_node("girl").global_position
		var session_version: int = session.session_version
		entrance._destination = destination
		entrance._enter_lobby()
		var target := "res://Scenes/SocialLobby.tscn" if destination == "social" else "res://Scenes/CustomizationLobby.tscn"
		check(await settled(target), destination + " real scene opens")
		if current_scene.scene_file_path != target: quit(1); return
		if destination == "social": manager.leave_social_lobby()
		else: manager.leave_character_customization()
		check(await settled("res://Scenes/world.tscn"), destination + " returns to new world")
		check(current_scene.get_node("girl").global_position.is_equal_approx(outdoor), "outdoor position preserved")
		check(session.session_version == session_version, "session preserved")
		check(not root.get_node("GameState").menu_open, "movement lock released")
	print("CAMPUS_ENTRANCES_RESULT failures=", failures)
	quit(failures)
