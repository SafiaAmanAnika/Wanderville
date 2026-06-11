extends Node2D

@onready var farm_layer: TileMapLayer = $"../Map/FarmLayer"

# Farm area boundary, in global/world coordinates (same units as
# player.global_position - the "Player at: ..." values printed below).
# The whole farming grid lives inside this rectangle - nothing outside it
# can ever be tilled.
const FARM_AREA_MIN := Vector2(-551, -194)
const FARM_AREA_MAX := Vector2(-301, 34)

# How many tiles to divide the farm area into (columns, rows). The farm area
# is split evenly into this many cells, so the grid always exactly fills
# FARM_AREA_MIN..FARM_AREA_MAX with no gaps and nothing sticking outside it.
# Tune this in the Inspector to make tiles bigger/smaller (fewer/more tiles).
@export var farm_grid_size: Vector2i = Vector2i(5, 5)

# Size of one tile, in world pixels - derived from the farm area and grid size.
func _get_tile_visual_size() -> Vector2:
	var area_size = FARM_AREA_MAX - FARM_AREA_MIN
	return Vector2(area_size.x / float(farm_grid_size.x), area_size.y / float(farm_grid_size.y))

# Growth settings
const GROWTH_STAGES = 3
const STAGE_DURATION = 5.0

# Crop data: tile_key -> {type, stage, watered, timer}
var active_crops: Dictionary = {}

# Tiles that have been tilled (key -> true)
var tilled_tiles: Dictionary = {}

func _ready():
	print("=== FARM CONTROLLER READY ===")
	print("FarmLayer exists: ", farm_layer != null)
	if farm_layer:
		print("FarmLayer tile_set exists: ", farm_layer.tile_set != null)

func _input(event):
	# Only act on E key press when NOT in menu
	if GameState.menu_open:
		return
	
	if event.is_action_pressed("interact"):
		print("=== E KEY PRESSED ===")
		print("farm_mode: ", GameState.farm_mode)
		
		if farm_layer == null:
			push_error("FarmLayer is null!")
			return
		
		# Get player position and convert to tile
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

		# Auto-progression: Empty -> Tilled -> Planted -> Watered -> Harvest
		if not tilled_tiles.has(key):
			# Empty ground - TILL it
			_till(tile_pos)
		else:
			# Already tilled - check if has crop
			if active_crops.has(key):
				var crop = active_crops[key]
				if crop.stage >= GROWTH_STAGES:
					# Ready to harvest
					_harvest(tile_pos, key)
				elif not crop.watered:
					# Needs water
					_water(tile_pos, key)
				else:
					# Already watered, waiting to grow
					print("GROWING... stage: ", crop.stage)
			else:
				# Tilled but no crop - PLANT
				_plant(tile_pos, key)

const SOIL_TEXTURE = preload("res://Assets/farming/soil.png")
const SOIL_REGION = Rect2(408, 106, 605, 556)  # cropped bounding box of the soil art in soil.png

# Render above FarmLayer (z_index 10) so the soil/crop sprites aren't hidden behind the tilemap
const VISUAL_Z_INDEX = 1

func _till(tile_pos: Vector2i):
	print(">>> TILLING <<<")

	var key = _key(tile_pos)
	tilled_tiles[key] = true

	# Show a tilled-soil sprite over the tile instead of a debug box
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

# Converts a global position into a tile coordinate, relative to the farm
# area's top-left corner (FARM_AREA_MIN). This is the SAME grid used for
# visuals, so "standing on the same tile" and "looking at the same tilled
# patch" always agree.
func _get_tile_pos(global_pos: Vector2) -> Vector2i:
	var size = _get_tile_visual_size()
	var rel = global_pos - FARM_AREA_MIN
	return Vector2i(floori(rel.x / size.x), floori(rel.y / size.y))

# True if this tile coordinate is one of the farm_grid_size x farm_grid_size
# cells that make up the farm area. Anything outside that grid - including
# negative coordinates or coordinates >= farm_grid_size - is outside the
# rectangle the user defined.
func _is_in_farm_area(tile_pos: Vector2i) -> bool:
	return tile_pos.x >= 0 and tile_pos.x < farm_grid_size.x \
		and tile_pos.y >= 0 and tile_pos.y < farm_grid_size.y

# Center of the given tile, in global space.
func _tile_to_world(tile_pos: Vector2i) -> Vector2:
	var size = _get_tile_visual_size()
	return FARM_AREA_MIN + Vector2(
		(tile_pos.x + 0.5) * size.x,
		(tile_pos.y + 0.5) * size.y
	)

func _plant(tile_pos: Vector2i, key: String):
	# Find first available seed
	var seed = ""
	for s in ["wheat", "corn", "cotton", "tulip"]:
		if GameState.seed_inventory.get(s, 0) > 0:
			seed = s
			break
	
	if seed == "":
		print("NO SEEDS AVAILABLE")
		return
	
	# Deduct seed
	GameState.seed_inventory[seed] -= 1
	GameState.seed_changed.emit(seed)
	
	# Store crop data
	active_crops[key] = {
		"type": seed,
		"stage": 0,
		"watered": false,
		"timer": 0.0
	}
	
	print(">>> PLANTED: ", seed, " <<<")
	_spawn_crop_visual(tile_pos, seed, 0)
	_sfx("plant")

func _water(tile_pos: Vector2i, key: String):
	if GameState.water_drops <= 0:
		print("NO WATER")
		return

	if not GameState.spend_water(1):
		return

	active_crops[key].watered = true

	# Darken the soil sprite to show it's watered
	var soil = get_node_or_null("Soil_" + key)
	if soil:
		soil.modulate = Color(0.6, 0.6, 0.9)

	print(">>> WATERED <<<")
	_sfx("water")

func _harvest(tile_pos: Vector2i, key: String):
	var crop = active_crops[key]
	var crop_type = crop.type
	print(">>> HARVESTED: ", crop_type, " <<<")

	# Remove visual
	var visual = get_node_or_null("CropVisual_" + key)
	if visual:
		visual.queue_free()

	# Remove data
	active_crops.erase(key)

	# Reset soil sprite back to its un-watered look (tile stays tilled)
	var soil = get_node_or_null("Soil_" + key)
	if soil:
		soil.modulate = Color(1, 1, 1)

	_sfx("harvest")

func _spawn_crop_visual(tile_pos: Vector2i, crop_type: String, stage: int):
	var key = _key(tile_pos)

	# Remove any previous visual for this tile so growth stages don't stack up
	var old = get_node_or_null("CropVisual_" + key)
	if old:
		remove_child(old)
		old.queue_free()

	var node = Node2D.new()
	node.name = "CropVisual_" + key
	node.z_index = VISUAL_Z_INDEX + 1
	
	var path = "res://Assets/farming/regular_crops/%s_spritesheet.png" % crop_type
	if crop_type == "paddy":
		path = "res://Assets/farming/regular_crops/paddy_spritesheet.png"

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
		# Placeholder for missing spritesheets
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
	# Growth tick
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