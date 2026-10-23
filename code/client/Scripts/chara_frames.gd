class_name CharaFrames
# Card picture for the character select screen (first idle frame, facing the camera)

const DIRECTIONS := ["front", "front_right", "right", "back_right", "back", "back_left", "left", "front_left"]
const ACTIONS := ["idle", "walk", "run", "hoe", "water", "fish", "scythe"]
const FILES := {"idle":"idle.png", "walk":"run.png", "run":"run.png", "hoe":"hoe.png", "water":"watering_can.png", "fish":"fishing.png", "scythe":"scythe.png"}
const CELL := Vector2i(448, 448)
static var _previews: Dictionary = {}
static var _stride_offsets: Dictionary = {}
static var _review_sheets: Dictionary = {}
const LONG_ROOT := "res://Assets/charas/long_leg_animations_v1/"

static func longer_leg_folder(folder: String) -> String:
	if OS.get_environment("GODOT_LONG_LEG_ART") != "1": return ""
	var candidate := LONG_ROOT + folder.get_file()
	# A character swaps only as a complete set; never mix short/long action art.
	for action in ACTIONS:
		if not FileAccess.file_exists(candidate.path_join(action + ".png")): return ""
	return candidate

static func _sheet(path: String) -> Texture2D:
	var source_path := ProjectSettings.globalize_path(path)
	var review := path.begins_with(LONG_ROOT) and FileAccess.file_exists(source_path)
	# Art review must show the current PNG even before the editor reimports it.
	# Share live textures between avatars without keeping retired casts in memory.
	var modified := FileAccess.get_modified_time(path) if review else 0
	if review and _review_sheets.has(path):
		var entry: Dictionary = _review_sheets[path]
		var cached := entry.texture.get_ref() as Texture2D
		if entry.modified == modified and cached != null: return cached
	if not review and ResourceLoader.exists(path) and FileAccess.file_exists(path + ".import"):
		return load(path) as Texture2D
	var image := Image.load_from_file(source_path)
	if image == null: return null
	var texture := ImageTexture.create_from_image(image)
	texture.resource_name = path
	if review: _review_sheets[path] = {"modified":modified, "texture":weakref(texture)}
	return texture

static func _head_anchor(image: Image, cell: Rect2i) -> Vector2:
	var bounds := image.get_region(cell).get_used_rect()
	# Locomotion has no overhead tools: the upper third contains the hat/head.
	# Measure its silhouette without letting a forward boot pull the centre.
	var left := 448
	var right := 0
	for y in range(bounds.position.y, bounds.position.y + maxi(1, roundi(bounds.size.y * 0.32))):
		for x in range(bounds.position.x, bounds.end.x):
			if image.get_pixel(cell.position.x + x, cell.position.y + y).a > 0.5:
				left = mini(left, x); right = maxi(right, x)
	return Vector2(roundf((left + right) * 0.5), bounds.position.y)

static func stride_offsets(folder: String, sheet: Texture2D) -> Array:
	if _stride_offsets.has(folder): return _stride_offsets[folder]
	var idle := load(folder.path_join("idle.png")) as Texture2D
	if idle == null: return []
	var original := sheet.get_image()
	var standing := idle.get_image()
	var offsets: Array = []
	for row in 8:
		var target := _head_anchor(standing, Rect2i(0, row * 448, 448, 448))
		for frame in 6:
			var anchor := _head_anchor(original, Rect2i(frame * 448, row * 448, 448, 448))
			# Shift the sampling window, not body parts or player/collision origins.
			offsets.append((anchor - target).round())
	_stride_offsets[folder] = offsets
	return offsets

static func add_sheet_animations(frames: SpriteFrames, folder: String, action: String, file: String, fps: float, loop: bool, replace: bool = false) -> void:
	var replacement := longer_leg_folder(folder)
	var path := folder.path_join(file) if replacement.is_empty() else replacement.path_join(action + ".png")
	if not FileAccess.file_exists(path): return
	var sheet := _sheet(path)
	if sheet == null or sheet.get_size() != Vector2(CELL.x * 6, CELL.y * 8): return
	var offsets := stride_offsets(folder, sheet) if replacement.is_empty() and action in ["walk", "run"] else []
	for row in DIRECTIONS.size():
		var name: String = action + "_" + DIRECTIONS[row]
		if frames.has_animation(name):
			if not replace: continue
			frames.remove_animation(name)
		frames.add_animation(name)
		frames.set_animation_speed(name, fps)
		frames.set_animation_loop(name, loop)
		for column in 6:
			var texture := AtlasTexture.new(); texture.atlas = sheet
			texture.region = Rect2(Vector2i(column, row) * CELL, CELL)
			if not offsets.is_empty():
				texture.region.position += offsets[row * 6 + column]
			frames.add_frame(name, texture)

static func preview_frames(folder: String, action: String = "idle") -> SpriteFrames:
	if not FILES.has(action): action = "idle"
	var key := folder + "/" + action + "/" + OS.get_environment("GODOT_LONG_LEG_ART")
	var review := longer_leg_folder(folder)
	if not review.is_empty(): key += "/" + str(FileAccess.get_modified_time(review.path_join(action + ".png")))
	if _previews.has(key): return _previews[key]
	var frames := SpriteFrames.new(); frames.remove_animation("default")
	add_sheet_animations(frames, folder, action, FILES[action], 10.0 if action == "run" else 6.0 if action in ["idle", "walk"] else 8.0, true)
	if _previews.size() >= 12: _previews.erase(_previews.keys()[0])
	_previews[key] = frames
	return frames

static func portrait(folder: String) -> Texture2D:
	var tex := AtlasTexture.new()
	tex.atlas = load(folder + "/idle.png")
	tex.region = Rect2(140, 130, 170, 200)   # crop around the body
	return tex
