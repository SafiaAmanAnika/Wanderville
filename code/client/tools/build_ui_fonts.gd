extends SceneTree
## Run without the game project to refresh the bundled, exportable font resources:
## godot --headless --path <empty-directory> --script <absolute-path-to-this-file>
func _initialize() -> void:
	var directory: String = get_script().resource_path.get_base_dir().path_join("../Assets/fonts").simplify_path()
	for family in ["DynaPuff", "Nunito"]:
		var font := FontFile.new()
		var error := font.load_dynamic_font(directory.path_join("sources/" + family + ".ttf"))
		if error == OK: error = ResourceSaver.save(font, directory.path_join(family + ".res"))
		if error != OK:
			push_error("Could not build " + family + ": " + error_string(error))
			quit(1)
			return
		print("Bundled UI font: ", family)
	quit()
