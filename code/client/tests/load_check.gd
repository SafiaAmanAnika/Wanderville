extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.get_node("APIClient").base_url = "http://127.0.0.1:1"
	var failures := 0
	for folder in ["res://Scripts", "res://autoloads"]:
		failures += _scripts(folder)
	for path in ["res://Scenes/world_hud.tscn", "res://Scenes/seed_picker_menu.tscn", "res://Scenes/social_panel.tscn", "res://Scenes/player1.tscn", "res://Scenes/menus/LoginScene.tscn", "res://Scenes/menus/SignupScene.tscn", "res://Scenes/menus/EmailVerificationScene.tscn", "res://Scenes/menus/MainMenu.tscn", "res://Scenes/menus/ProfileScene.tscn", "res://Scenes/menus/CharacterSelectScreen.tscn", "res://Scenes/menus/SettingsOverlay.tscn", "res://Scenes/CustomizationLobby.tscn", "res://Scenes/customization_interactions.tscn", "res://Scenes/marketplace.tscn"]:
		var scene := load(path) as PackedScene
		if scene == null:
			print("CLIENT_LOAD_FAIL ", path)
			failures += 1
			continue
		var instance := scene.instantiate()
		root.add_child(instance)
		await process_frame
		instance.queue_free()
		await process_frame
	print("CLIENT_LOAD_CHECK failures=", failures)
	quit(failures)

func _scripts(folder: String) -> int:
	var failures := 0
	for file in DirAccess.get_files_at(folder):
		if file.ends_with(".gd"):
			var script := load(folder.path_join(file)) as GDScript
			if script == null or not script.can_instantiate():
				print("CLIENT_LOAD_FAIL ", folder.path_join(file))
				failures += 1
	for child in DirAccess.get_directories_at(folder):
		failures += _scripts(folder.path_join(child))
	return failures
