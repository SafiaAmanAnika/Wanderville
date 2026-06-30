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

const GROWTH_STAGES = 4

var active_crops: Dictionary = {}
var tilled_tiles: Dictionary = {}

const SOIL_TEXTURE = preload("res://Assets/farming/soil.png")
const SOIL_REGION = Rect2(408, 106, 605, 556)
const VISUAL_Z_INDEX = 1

func _ready():
	print("=== FARM CONTROLLER READY ===")
	print("FarmLayer exists: ", farm_layer != null)
	if farm_layer:
		print("FarmLayer tile_set exists: ", farm_layer.tile_set != null)
	seed_picker.seed_selected.connect(_on_seed_selected)

func _input(event):
	if GameState.menu_open:
		return
	if not event.is_action_pressed("interact"):
		return

	if farm_layer == null:
		push_error("FarmLayer is null!")
		return

	var player = get_tree().get_first_node_in_group("player")
	if not player:
		push_error("No player found!")
		return

	var tile_pos = _get_tile_pos(player.global_position)
	var key = _key(tile_pos)

	if not _is_in_farm_area(tile_pos):
		print("Outside farm area")
		return

	if not tilled_tiles.has(key):
		_till(tile_pos)
	elif not active_crops.has(key):
		_plant(tile_pos, key)
	else:
		var crop = active_crops[key]
		if crop.stage >= GROWTH_STAGES:
			_harvest(tile_pos, key)
		elif not crop.watered:
			_water(tile_pos, key)
		else:
			print("GROWING... stage: ", crop.stage)
			
	print("Tile key: ", key, " Has crop: ", active_crops.has(key))

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
		"watered": false
	}
	print(">>> PLANTED: ", seed_name, " <<<")
	_spawn_crop_visual(_pending_tile_pos, seed_name)
	_sfx("plant")

func _water(tile_pos: Vector2i, key: String):
	if not GameState.spend_water(1):
		print("NO WATER")
		return
	active_crops[key].watered = true

	var crop_root = get_node_or_null("CropVisual_" + key)
	if crop_root:
		var anim = crop_root.get_node_or_null("AnimatedSprite2D")
		if anim:
			anim.water()

	print(">>> WATERED <<<")
	_sfx("water")

func _harvest(tile_pos: Vector2i, key: String):
	print(">>> HARVESTED: ", active_crops[key].type, " <<<")
	var visual = get_node_or_null("CropVisual_" + key)
	if visual:
		visual.queue_free()
	active_crops.erase(key)
	# Restore soil after harvest
	_till(tile_pos)
	_sfx("harvest")

func _spawn_crop_visual(tile_pos: Vector2i, crop_type: String) -> void:
	var key = _key(tile_pos)

	# Remove existing crop visual
	var old = get_node_or_null("CropVisual_" + key)
	if old:
		old.queue_free()

	# Remove soil — crop scene frame 0 shows seed on soil already
	var soil = get_node_or_null("Soil_" + key)
	if soil:
		soil.queue_free()

	var path = "res://Scenes/crops/%s.tscn" % crop_type
	if not ResourceLoader.exists(path):
		print("No scene for: ", crop_type, " - using placeholder")
		var tile_world_size = _get_tile_visual_size()
		var rect = ColorRect.new()
		rect.name = "CropVisual_" + key
		rect.size = tile_world_size
		rect.position = -tile_world_size / 2.0
		rect.color = Color(0.6, 0.8, 0.4)
		rect.z_index = VISUAL_Z_INDEX
		add_child(rect)
		rect.global_position = _tile_to_world(tile_pos)
		return

	var node: Node = load(path).instantiate()
	node.name = "CropVisual_" + key
	node.z_index = VISUAL_Z_INDEX
	add_child(node)
	node.global_position = _tile_to_world(tile_pos)

	var anim = node.get_node_or_null("AnimatedSprite2D")
	if anim:
		anim.fully_grown.connect(_on_crop_fully_grown.bind(key))
		var frame_tex = anim.sprite_frames.get_frame_texture("default", 0)
		if frame_tex:
			var frame_size = frame_tex.get_size()
			var anim_scale = anim.scale
			if frame_size.x > 0 and frame_size.y > 0 and anim_scale.x > 0:
				node.scale = 1.5 * _get_tile_visual_size() / (frame_size * anim_scale)

func _on_crop_fully_grown(key: String) -> void:
	if active_crops.has(key):
		active_crops[key].stage = GROWTH_STAGES
		print(">>> FULLY GROWN: ", active_crops[key].type)

func _get_tile_pos(global_pos: Vector2) -> Vector2i:
	var size = _get_tile_visual_size()
	var rel = global_pos - FARM_AREA_MIN
	return Vector2i(roundi(rel.x / size.x), roundi(rel.y / size.y))

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

func _key(tile: Vector2i) -> String:
	return "%d,%d" % [tile.x, tile.y]

func _str_to_vec(s: String) -> Vector2i:
	var parts = s.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))

func _sfx(name: String):
	pass
