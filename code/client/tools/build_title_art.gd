extends SceneTree
## godot --headless --path <empty-directory> --script <absolute-path-to-this-file>
## Bundle original PNG artwork in portable, lossless resources for packaged games.
func _initialize() -> void:
	var directory: String = get_script().resource_path.get_base_dir().path_join("../Assets").simplify_path()
	for item in [["background/Wanderville_Logo.png", "ui/title/logo.res"], ["ui/title/cream-card.png", "ui/title/cream-card.res"], ["ui/title/selection-cat.png", "ui/title/selection-cat.res"], ["ui/auth/parchment-frame.png", "ui/auth/parchment-frame.res"]]:
		var image := Image.load_from_file(directory.path_join(item[0]))
		if image == null:
			quit(1)
			return
		var texture := PortableCompressedTexture2D.new()
		texture.keep_compressed_buffer = true
		texture.create_from_image(image, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS)
		var trimmed := AtlasTexture.new()
		trimmed.atlas = texture
		trimmed.region = image.get_used_rect()
		if item[0].ends_with("selection-cat.png"):
			# Ignore imperceptible alpha specks when sizing the separate sprite.
			var bounds := Rect2i()
			for y in image.get_height():
				for x in image.get_width():
					if image.get_pixel(x,y).a >= 0.5:
						var pixel := Rect2i(x,y,1,1)
						bounds = pixel if not bounds.has_area() else bounds.merge(pixel)
			trimmed.region = bounds.grow(2).intersection(Rect2i(Vector2i.ZERO,image.get_size()))
		var error := ResourceSaver.save(trimmed, directory.path_join(item[1]))
		if error != OK:
			push_error(error_string(error))
			quit(1)
			return
		print(item[1], " region=", trimmed.region)
	quit()
