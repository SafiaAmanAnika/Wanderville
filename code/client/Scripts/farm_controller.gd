extends Node2D

@onready var farm_layer: TileMapLayer = $"../Map/FarmLayer"
@onready var seed_picker = $SeedPickerMenu

var _pending_tile_pos: Vector2i
var _pending_key: String

const FARM_AREA_MIN := Vector2(8629.15, -3797.821)
const FARM_AREA_MAX := Vector2(11129.43, -693.0)

@export var tile_visual_size: Vector2 = Vector2(50, 50)

func _get_tile_visual_size() -> Vector2:
	return tile_visual_size

const GROWTH_STAGES = 3
const STAGE_DURATION = 5.0

var active_crops: Dictionary = {}
var tilled_tiles: Dictionary = {}

func _ready():
	print("=== FARM CONTROLLER READY ===")
	print("FarmLayer exists: ", farm_layer != null)
	if farm_layer:
		print("FarmLayer tile_set exists: ", farm_layer.tile_set != null)
	seed_picker.seed_selected.connect(_on_seed_selected)

func _input(event):
	if GameState.menu_open:
		return
	if event.is_action_pressed("interact"):
		print("=== E KEY PRESSED ===")
		if farm_layer == null:
			push_error("FarmLayer is null!")
			return
		var player = get_tree().get_first_node_in_group("player")
		if not player:
			push_error("No player found!")
			return
		var player_pos = player.global_position
		var tile_pos = _get_tile_pos(player_pos)
		var key = _key(tile_pos)
		print("Player at: ", player_pos)
		print("Tile pos: ", tile_pos, " Tilled: ", tilled_tiles.has(key))
		if not _is_in_farm_area(tile_pos):
			print("Outside farm area - can't farm here")
			return
		if not tilled_tiles.has(key):
			_till(tile_pos)
		else:
			if active_crops.has(key):
				var crop = active_crops[key]
				if crop.stage >= GROWTH_STAGES:
					_harvest(tile_pos, key)
				elif not crop.watered:
					_water(tile_pos, key)
				else:
					print("GROWING... stage: ", crop.stage)
			else:
				_plant(tile_pos, key)

const SOIL_TEXTURE = preload("res://Assets/farming/soil.png")
const SOIL_REGION = Rect2(408, 106, 605, 556)
const VISUAL_Z_INDEX = 1

func _till(tile_pos: Vector2i):
	print(">>> TILLING <<<")
	var key = _key(tile_pos)
	tilled_tiles[key] = true
	var soil = Sprite2D.new()
	soil.name = "Soil_" + key
	soil.texture = SOIL_TEXTURE
	soil.region_enabled = true
	soil.region_rect = SOIL_REGION
	soil.centered = true
	soil.z_index = VISUAL_Z_INDEX
	soil.scale = _get_tile_visual_size() / Vector2(SOIL_REGION.size)
	add_child(soil)
	soil.global_position = _tile_to_world(tile_pos)
	_sfx("till")

func _get_tile_pos(global_pos: Vector2) -> Vector2i:
	var size = _get_tile_visual_size()
	var rel = global_pos - FARM_AREA_MIN
	return Vector2i(floori(rel.x / size.x), floori(rel.y / size.y))

func _is_in_farm_area(tile_pos: Vector2i) -> bool:
	var center = _tile_to_world(tile_pos)
	return center.x >= FARM_AREA_MIN.x and center.x <= FARM_AREA_MAX.x \
		and center.y >= FARM_AREA_MIN.y and center.y <= FARM_AREA_MAX.y

func _tile_to_world(tile_pos: Vector2i) -> Vector2:
	var size = _get_tile_visual_size()
	return FARM_AREA_MIN + Vector2(
		(tile_pos.x + 0.5) * size.x,
		(tile_pos.y + 0.5) * size.y
	)

func _plant(tile_pos: Vector2i, key: String):
	var has_seeds := false
	for s in GameState.seed_inventory:
		if GameState.seed_inventory[s] > 0:
			has_seeds = true
			break
	if not has_seeds:
		print("NO SEEDS AVAILABLE")
		return
	_pending_tile_pos = tile_pos
	_pending_key = key
	seed_picker.show_menu()

func _on_seed_selected(seed_name: String) -> void:
	GameState.seed_inventory[seed_name] -= 1
	GameState.seed_changed.emit(seed_name)
	active_crops[_pending_key] = {
		"type": seed_name,
		"stage": 0,
		"watered": false,
		"timer": 0.0
	}
	print(">>> PLANTED: ", seed_name, " <<<")
	_spawn_crop_visual(_pending_tile_pos, seed_name, 0)
	_sfx("plant")

func _water(tile_pos: Vector2i, key: String):
	if GameState.water_drops <= 0:
		print("NO WATER")
		return
	if not GameState.spend_water(1):
		return
	active_crops[key].watered = true
	var soil = get_node_or_null("Soil_" + key)
	if soil:
		soil.modulate = Color(0.6, 0.6, 0.9)
	print(">>> WATERED <<<")
	_sfx("water")

func _harvest(tile_pos: Vector2i, key: String):
	var crop = active_crops[key]
	var crop_type = crop.type
	print(">>> HARVESTED: ", crop_type, " <<<")
	var visual = get_node_or_null("CropVisual_" + key)
	if visual:
		visual.queue_free()
	active_crops.erase(key)
	var soil = get_node_or_null("Soil_" + key)
	if soil:
		soil.modulate = Color(1, 1, 1)
	_sfx("harvest")

func _spawn_crop_visual(tile_pos: Vector2i, crop_type: String, stage: int):
	var key = _key(tile_pos)
	var old = get_node_or_null("CropVisual_" + key)
	if old:
		remove_child(old)
		old.queue_free()
	var node = Node2D.new()
	node.name = "CropVisual_" + key
	node.z_index = VISUAL_Z_INDEX + 1
	var path = "res://Assets/farming/regular_crops/%s_spritesheet.png" % crop_type
	var tile_world_size = _get_tile_visual_size()
	if ResourceLoader.exists(path):
		var tex = load(path)
		var sprite = Sprite2D.new()
		sprite.texture = tex
		sprite.region_enabled = true
		sprite.centered = true
		var frame_w = tex.get_width() / 4
		var frame_h = 32
		if tex.get_height() < frame_h:
			frame_h = tex.get_height()
		sprite.region_rect = Rect2(stage * frame_w, 0, frame_w, frame_h)
		sprite.scale = tile_world_size / Vector2(frame_w, frame_h)
		node.add_child(sprite)
	else:
		var rect = ColorRect.new()
		rect.size = tile_world_size
		rect.position = -tile_world_size / 2.0
		rect.color = _crop_color(crop_type)
		node.add_child(rect)
	add_child(node)
	node.global_position = _tile_to_world(tile_pos)

func _crop_color(crop_type: String) -> Color:
	match crop_type:
		"wheat":  return Color(0.95, 0.85, 0.4)
		"corn":   return Color(0.9, 0.75, 0.2)
		"cotton": return Color(0.85, 0.85, 0.9)
		"tulip":  return Color(0.9, 0.3, 0.4)
		"paddy":  return Color(0.7, 0.85, 0.4)
		_:        return Color(0.6, 0.8, 0.4)

func _process(delta):
	for key in active_crops.keys():
		var crop = active_crops[key]
		if not crop.watered:
			continue
		crop.timer += delta
		if crop.timer >= STAGE_DURATION:
			crop.timer = 0.0
			if crop.stage < GROWTH_STAGES:
				crop.stage += 1
				var tile_pos = _str_to_vec(key)
				_spawn_crop_visual(tile_pos, crop.type, crop.stage)
				print("Crop grew to stage: ", crop.stage)

func _key(tile: Vector2i) -> String:
	return "%d,%d" % [tile.x, tile.y]

func _str_to_vec(s: String) -> Vector2i:
	var parts = s.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))

func _sfx(name: String):
	pass
