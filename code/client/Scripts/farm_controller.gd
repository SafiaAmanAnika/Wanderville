extends Node2D

@onready var farm_layer: TileMapLayer = $"../Map/FarmLayer"

# UPDATE THESE: Your actual soil tile coordinates from the TileMap palette
const SOIL_TILLED   = Vector2i(22, 48)
const SOIL_WATERED  = Vector2i(22, 48)
const SOIL_SOURCE_ID = 0

# Growth settings
const GROWTH_STAGES = 3
const STAGE_DURATION = 5.0

# Crop data: tile_key -> {type, stage, watered, timer}
var active_crops: Dictionary = {}

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
		var local_pos = farm_layer.to_local(player_pos)
		var tile_pos = farm_layer.local_to_map(local_pos)
		var current = farm_layer.get_cell_atlas_coords(tile_pos)
		
		print("Player at: ", player_pos)
		print("Tile pos: ", tile_pos, " Current tile: ", current)
		
		# Auto-progression: Empty -> Tilled -> Planted -> Watered -> Harvest
		match current:
			Vector2i(-1, -1):
				# Empty ground - TILL it
				_till(tile_pos)
			SOIL_TILLED, SOIL_WATERED:
				# Already tilled - check if has crop
				var key = _key(tile_pos)
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
			_:
				print("Unknown tile state: ", current)

func _till(tile_pos: Vector2i):
	print(">>> TILLING <<<")
	farm_layer.set_cell(tile_pos, SOIL_SOURCE_ID, SOIL_TILLED)
	
	# DEBUG: Force the tile to be super obvious
	var debug = ColorRect.new()
	debug.size = Vector2(100, 100)
	debug.position = farm_layer.to_global(farm_layer.map_to_local(tile_pos)) - Vector2(50, 50)
	debug.color = Color(1, 0, 0, 0.5)  # Big red semi-transparent square
	debug.z_index = 100
	add_child(debug)
	
	_sfx("till")

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
	
	farm_layer.set_cell(tile_pos, SOIL_SOURCE_ID, SOIL_WATERED)
	active_crops[key].watered = true
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
	
	# Reset tile to tilled
	farm_layer.set_cell(tile_pos, SOIL_SOURCE_ID, SOIL_TILLED)
	_sfx("harvest")

func _spawn_crop_visual(tile_pos: Vector2i, crop_type: String, stage: int):
	var key = _key(tile_pos)
	var node = Node2D.new()
	node.name = "CropVisual_" + key
	node.position = farm_layer.to_global(farm_layer.map_to_local(tile_pos))
	node.z_index = 2
	
	var path = "res://Assets/farming/regular_crops/%s_spritesheet.png" % crop_type
	if crop_type == "paddy":
		path = "res://Assets/farming/regular_crops/paddy_spritesheet.png"
	
	if ResourceLoader.exists(path):
		var tex = load(path)
		var sprite = Sprite2D.new()
		sprite.texture = tex
		sprite.region_enabled = true
		sprite.centered = true
		sprite.scale = Vector2(2, 2)
		
		var frame_w = tex.get_width() / 4
		var frame_h = 32
		if tex.get_height() < frame_h:
			frame_h = tex.get_height()
		sprite.region_rect = Rect2(stage * frame_w, 0, frame_w, frame_h)
		
		node.add_child(sprite)
	else:
		# Placeholder for missing spritesheets
		var rect = ColorRect.new()
		rect.size = Vector2(48, 48)
		rect.position = Vector2(-24, -24)
		rect.color = _crop_color(crop_type)
		node.add_child(rect)
	
	add_child(node)

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
