extends RefCounted
# One place that knows what a crop looks like.
#
# Deliberately no class_name: consumers preload it as
#   const CROP_ART = preload("res://Scripts/crop_catalog.gd")
# which resolves at parse time, with no global class registration to go stale.
#
# Every crop is a single spritesheet in Assets/farming: five growth stages in a
# row. crop_manifest.json records the frame size, how many frames there are, and
# the planting point - the pixel where the stem meets the soil - so a crop can be
# stood on its tile instead of floating over it.
#
#   CROP_ART.frame(code, 0)        -> a seed icon (first stage)
#   CROP_ART.frame(code, -1)       -> a harvested crop icon (last stage)
#   CROP_ART.info(code)            -> the manifest row, {} if the crop has no art
#   CROP_ART.ids()                 -> every crop that has art
#
# Nothing here reads a path the server sent: a code only ever selects a row that
# already exists in the manifest shipped with the game.

const MANIFEST_PATH := "res://Assets/farming/crop_manifest.json"
const ASSET_ROOT := "res://Assets/farming/"

const FRAME_SIZE_FALLBACK := Vector2(429, 724)
const PLANT_POINT_FALLBACK := Vector2(214, 530)

static var _crops: Dictionary = {}      # "wheat" -> manifest row
static var _sheets: Dictionary = {}     # "wheat" -> Texture2D (or null)
static var _frames: Dictionary = {}     # "wheat:0" -> AtlasTexture
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		push_warning("crop_manifest.json not found - crops have no art")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_warning("crop_manifest.json could not be read")
		return
	for crop in parsed.get("crops", []):
		_crops[str(crop.get("id", ""))] = crop


## Every crop that has art, sorted. Use this rather than a hand-written list.
static func ids() -> Array:
	_load()
	var out := _crops.keys()
	out.sort()
	return out


## The manifest row for a crop, or {} if it has none. A "wheat_seed" code works
## too: the seed and the crop it grows share one spritesheet.
static func info(code: String) -> Dictionary:
	_load()
	return _crops.get(_crop_of(code), {})


static func has(code: String) -> bool:
	_load()
	return _crops.has(_crop_of(code))


static func _crop_of(code: String) -> String:
	return code.trim_suffix("_seed")


## Frame size in pixels, from the manifest.
static func frame_size(code: String) -> Vector2:
	return _pair(info(code), "frame_size", FRAME_SIZE_FALLBACK)


## Where the stem meets the soil, in frame pixels.
static func planting_point(code: String) -> Vector2:
	return _pair(info(code), "planting_point", PLANT_POINT_FALLBACK)


## How many growth stages this crop has.
static func stage_count(code: String) -> int:
	return int(info(code).get("hframes", 5))


## The whole spritesheet, loaded once and kept. null when the crop has no art.
static func sheet(code: String) -> Texture2D:
	var crop := _crop_of(code)
	if _sheets.has(crop):
		return _sheets[crop]
	var row := info(crop)
	var path := ASSET_ROOT + str(row.get("sheet", ""))
	if row.is_empty() or not ResourceLoader.exists(path):
		_sheets[crop] = null
		return null
	_sheets[crop] = load(path) as Texture2D
	return _sheets[crop]


## One growth stage as its own texture. index 0 is the seed, -1 the ripe crop.
## Returns null when the crop has no art, so callers can fall back.
static func frame(code: String, index: int) -> Texture2D:
	var crop := _crop_of(code)
	var stages := stage_count(crop)
	var wanted := index if index >= 0 else stages + index
	wanted = clampi(wanted, 0, maxi(stages - 1, 0))
	var cache_key := "%s:%d" % [crop, wanted]
	if _frames.has(cache_key):
		return _frames[cache_key]
	var texture := sheet(crop)
	if texture == null:
		_frames[cache_key] = null
		return null
	var size := frame_size(crop)
	var slice := AtlasTexture.new()
	slice.atlas = texture
	slice.region = Rect2(Vector2(size.x * wanted, 0.0), size)
	_frames[cache_key] = slice
	return slice


## The icon for an inventory row, seed or crop: the ripe plant, which is the only
## stage that reads at icon size. Stage 0 is a few pixels of seed and shows up
## blank in the store and the seed picker.
static func icon(code: String) -> Texture2D:
	return frame(code, -1)


## All five stages, ready for an AnimatedSprite2D. null when the crop has no art.
static func sprite_frames(code: String) -> SpriteFrames:
	var texture := sheet(code)
	if texture == null:
		return null
	var crop := _crop_of(code)
	var size := frame_size(crop)
	var out := SpriteFrames.new()
	out.clear("default")
	for i in stage_count(crop):
		var slice := AtlasTexture.new()
		slice.atlas = texture
		slice.region = Rect2(Vector2(size.x * i, 0.0), size)
		out.add_frame("default", slice)
	return out


static func _pair(row: Dictionary, field: String, fallback: Vector2) -> Vector2:
	var raw: Variant = row.get(field)
	if raw is Array and raw.size() >= 2:
		return Vector2(float(raw[0]), float(raw[1]))
	return fallback
