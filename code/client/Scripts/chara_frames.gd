class_name CharaFrames
# Shared animation slicing for the six original characters.
# Every frame uses a fixed 448x448 cell. Do not shift the atlas crop based on
# the head position: doing so can sample pixels from adjacent cells and make
# animation frames visibly jump or clip. Correct artwork alignment at source.

const DIRECTIONS := ["front", "front_right", "right", "back_right", "back", "back_left", "left", "front_left"]
const ACTIONS := ["idle", "walk", "hoe", "water", "fish", "scythe", "fill_bucket"]
const FILES := {"idle":"idle.png", "walk":"walk.png", "hoe":"hoe.png", "water":"watering_can.png", "fish":"fishing.png", "scythe":"scythe.png", "fill_bucket":"fill_bucket.png"}
const CELL := Vector2i(448, 448)
# Shared world-space scale for the six 448px character sets.
const GAMEPLAY_SCALE := Vector2(0.9, 0.9)
const LONG_ROOT := "res://Assets/charas/long_leg_animations_v1/"
const MODEL_ROOT := "res://Assets/charas/complete_animations/"
const FPS := {"idle":6.0, "walk":8.0, "hoe":8.0, "water":8.0, "scythe":8.0, "fish":8.0, "fill_bucket":8.0}
const MODELS := {"CharacterA":"blue_female", "CharacterB":"green_female", "CharacterC":"red_female", "CharacterA_Male":"blue_male", "CharacterB_Male":"green_male", "CharacterC_Male":"red_male"}

static var _previews: Dictionary = {}
static var _review_sheets: Dictionary = {}


static func longer_leg_folder(folder: String) -> String:
	if OS.get_environment("GODOT_LONG_LEG_ART") != "1":
		return ""
	var candidate := LONG_ROOT + folder.get_file()
	# Change art only when a complete compatible set exists.
	for action in ACTIONS:
		if not FileAccess.file_exists(candidate.path_join(action + ".png")):
			return ""
	return candidate


static func _sheet(path: String) -> Texture2D:
	var source_path := ProjectSettings.globalize_path(path)
	var review := path.begins_with(LONG_ROOT) and FileAccess.file_exists(source_path)
	var modified := FileAccess.get_modified_time(path) if review else 0
	if review and _review_sheets.has(path):
		var entry: Dictionary = _review_sheets[path]
		var cached := entry.texture.get_ref() as Texture2D
		if entry.modified == modified and cached != null:
			return cached
	if not review and ResourceLoader.exists(path) and FileAccess.file_exists(path + ".import"):
		return load(path) as Texture2D
	var image := Image.load_from_file(source_path)
	if image == null:
		return null
	var texture := ImageTexture.create_from_image(image)
	texture.resource_name = path
	if review:
		_review_sheets[path] = {"modified": modified, "texture": weakref(texture)}
	return texture


static func add_sheet_animations(frames: SpriteFrames, folder: String, action: String, file: String, fps: float, loop: bool, replace: bool = false) -> void:
	var replacement := longer_leg_folder(folder)
	var path := folder.path_join(file) if replacement.is_empty() else replacement.path_join(action + ".png")
	var supplied := action in ACTIONS and MODELS.has(folder.get_file())
	var columns := 6
	if supplied:
		path = MODEL_ROOT + MODELS[folder.get_file()] + "/" + action + ".png"
		columns = 8
		fps = FPS[action]
	if not FileAccess.file_exists(path):
		return
	var sheet := _sheet(path)
	if sheet == null or sheet.get_size() != Vector2(CELL.x * columns, CELL.y * 8):
		push_warning("Invalid character sprite sheet dimensions: " + path)
		return
	for row in DIRECTIONS.size():
		var name: String = action + "_" + DIRECTIONS[row]
		if frames.has_animation(name):
			if not replace:
				continue
			frames.remove_animation(name)
		frames.add_animation(name)
		frames.set_animation_speed(name, fps)
		frames.set_animation_loop(name, loop)
		for column in columns:
			var texture := AtlasTexture.new()
			texture.atlas = sheet
			# Fixed grid sampling. Every animation action uses exactly the same cells.
			texture.region = Rect2(Vector2i(column, row) * CELL, CELL)
			frames.add_frame(name, texture)


static func preview_frames(folder: String, action: String = "idle") -> SpriteFrames:
	if not FILES.has(action):
		action = "idle"
	var key := folder + "/" + action + "/" + OS.get_environment("GODOT_LONG_LEG_ART")
	var review := longer_leg_folder(folder)
	if not review.is_empty():
		key += "/" + str(FileAccess.get_modified_time(review.path_join(action + ".png")))
	if _previews.has(key):
		return _previews[key]
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var fps := 10.0 if action == "run" else 6.0 if action in ["idle", "walk"] else 8.0
	add_sheet_animations(frames, folder, action, FILES[action], fps, true)
	if _previews.size() >= 12:
		_previews.erase(_previews.keys()[0])
	_previews[key] = frames
	return frames


static func portrait(folder: String) -> Texture2D:
	var tex := AtlasTexture.new()
	if MODELS.has(folder.get_file()):
		tex.atlas = _sheet(MODEL_ROOT + MODELS[folder.get_file()] + "/idle.png")
		tex.region = Rect2(112, 96, 224, 232)
		return tex
	tex.atlas = load(folder + "/idle.png")
	tex.region = Rect2(140, 130, 170, 200)
	return tex
