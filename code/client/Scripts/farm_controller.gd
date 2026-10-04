extends Node2D

@onready var farm_layer: TileMapLayer = $"../Map/FarmLayer"
@onready var seed_picker = $SeedPickerMenu

var _pending_tile_pos: Vector2i
var _pending_key: String

var _dragging: bool = false
var _drag_key: String = ""
var _drag_crop: Dictionary = {}

const FARM_AREA_MIN := Vector2(8629.15, -3797.821)
const FARM_AREA_MAX := Vector2(11129.43, -693.0)

@export var tile_visual_size: Vector2 = Vector2(50, 50)

func _get_tile_visual_size() -> Vector2:
	return tile_visual_size

const GROWTH_STAGES = 4

var _backend_busy := false
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
	GameState.farm_updated.connect(_apply_server_plots)
	_apply_server_plots(GameState.farm_plots)

func _input(event):
	if GameState.menu_open or GameState.social_open or _backend_busy or (Global.is_logged_in() and not GameState.backend_ready):
		return

	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return

	var tile_pos = _get_tile_pos(player.global_position)
	var key = _key(tile_pos)

	# --- DRAG CROP (hold M) ---
	if event.is_action_pressed("move_crop"):
		if not _dragging:
			# PICK UP - find nearest crop
			var nearest_key: String = ""
			var nearest_dist: float = INF
			for crop_key in active_crops.keys():
				var crop_world = _tile_to_world(_str_to_vec(crop_key))
				var dist = player.global_position.distance_to(crop_world)
				if dist < tile_visual_size.x * 4.0 and dist < nearest_dist:
					nearest_dist = dist
					nearest_key = crop_key
			if nearest_key == "":
				print("No crop nearby")
				return
			_drag_key = nearest_key
			_drag_crop = active_crops[nearest_key].duplicate()
			if not Global.is_logged_in():
				active_crops.erase(nearest_key)
			var visual = get_node_or_null("CropVisual_" + nearest_key)
			if visual:
				visual.z_index = VISUAL_Z_INDEX + 5
				var body = visual.get_node_or_null("StaticBody2D/CollisionShape2D")
				if body:
					body.set_deferred("disabled", true)
			_dragging = true
			print(">>> PICKED UP: ", _drag_crop.type)
		else:
			# DROP - place at current player tile
			var drop_tile = _get_tile_pos(player.global_position)
			var drop_key = _key(drop_tile)
			if Global.is_logged_in():
				await _relocate(drop_tile)
				return
			var visual = get_node_or_null("CropVisual_" + _drag_key)
			if _is_in_farm_area(drop_tile) and tilled_tiles.has(drop_key) and not active_crops.has(drop_key):
				if visual:
					visual.name = "CropVisual_" + drop_key
					visual.global_position = _tile_to_world(drop_tile)
					visual.z_index = VISUAL_Z_INDEX
					var body = visual.get_node_or_null("StaticBody2D/CollisionShape2D")
					if body:
						body.set_deferred("disabled", false)
				active_crops[drop_key] = _drag_crop
				_till(_str_to_vec(_drag_key))
				print(">>> DROPPED at: ", drop_key)
			else:
				# Invalid — return to original
				if visual:
					visual.global_position = _tile_to_world(_str_to_vec(_drag_key))
					visual.z_index = VISUAL_Z_INDEX
					var body = visual.get_node_or_null("StaticBody2D")
					if body:
						body.set_deferred("disabled", false)
				active_crops[_drag_key] = _drag_crop
				print(">>> RETURNED: ", _drag_crop.type)
			_dragging = false
			_drag_key = ""
			_drag_crop = {}
		return
	# --- INTERACT (E) ---
	if not event.is_action_pressed("interact"):
		return
	if farm_layer == null:
		push_error("FarmLayer is null!")
		return
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

func _process(_delta):
	if not _dragging:
		return

	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return

	var visual = get_node_or_null("CropVisual_" + _drag_key)
	if visual:
		# Carry the crop above the player
		visual.global_position = player.global_position + Vector2(0, -32)
func _till(tile_pos: Vector2i):
	if Global.is_logged_in():
		await _server_action("till", tile_pos, _key(tile_pos))
		return
	_draw_soil(tile_pos)

func _draw_soil(tile_pos: Vector2i):
	print(">>> TILLING <<<")
	var key = _key(tile_pos)
	tilled_tiles[key] = true
	if get_node_or_null("Soil_" + key) != null:
		return
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
	_pending_tile_pos = tile_pos
	_pending_key = key
	seed_picker.show_menu()

func _on_seed_selected(seed_name: String) -> void:
	if Global.is_logged_in():
		await _server_action("plant", _pending_tile_pos, _pending_key, seed_name)
		return
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
	if Global.is_logged_in():
		await _server_action("water", tile_pos, key)
		return
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
	if Global.is_logged_in():
		await _server_action("harvest", tile_pos, key)
		return
	print(">>> HARVESTED: ", active_crops[key].type, " <<<")
	var visual = get_node_or_null("CropVisual_" + key)
	if visual:
		visual.queue_free()
	active_crops.erase(key)
	_till(tile_pos)
	_sfx("harvest")

func _spawn_crop_visual(tile_pos: Vector2i, crop_type: String) -> void:
	var key = _key(tile_pos)
	var old = get_node_or_null("CropVisual_" + key)
	if old:
		remove_child(old)
		old.queue_free()
	var soil = get_node_or_null("Soil_" + key)
	if soil:
		remove_child(soil)
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
		anim.fully_grown.connect(_on_crop_fully_grown.bind(key), CONNECT_ONE_SHOT)
		var frame_tex = anim.sprite_frames.get_frame_texture("default", 0)
		if frame_tex:
			var frame_size = frame_tex.get_size()
			var anim_scale = anim.scale
			if frame_size.x > 0 and frame_size.y > 0 and anim_scale.x > 0:
				node.scale = 1.5 * _get_tile_visual_size() / (frame_size * anim_scale)

func _on_crop_fully_grown(key: String) -> void:
	if Global.is_logged_in():
		return
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


func _server_action(action: String, tile: Vector2i, key: String, seed: String = "") -> void:
	if _backend_busy or not GameState.backend_ready:
		return
	_backend_busy = true
	var version := Global.session_version
	var response: Dictionary
	match action:
		"till":
			response = await APIClient.till_tile(tile.x, tile.y)
		"plant":
			response = await APIClient.plant_crop(Global.token, tile.x, tile.y, seed + "_seed")
		"water":
			response = await APIClient.water_crop(Global.token, int(active_crops[key]["plot_id"]))
		"harvest":
			response = await APIClient.harvest_crop(Global.token, int(active_crops[key]["plot_id"]))
	_backend_busy = false
	if version != Global.session_version:
		return
	if bool(response.get("ok", false)):
		var data: Variant = APIClient.data_of(response)
		if data is Dictionary:
			var plot: Dictionary = data.get("plot", data)
			_apply_plot(plot)
		_sfx(action)
	else:
		GameState.report_error(response)
	await GameState.refresh_gameplay()


func _apply_server_plots(plots: Array) -> void:
	if _backend_busy or _dragging:
		return
	for plot in plots:
		_apply_plot(plot)


func _apply_plot(plot: Dictionary) -> void:
	var tile := Vector2i(int(plot.get("x", 0)), int(plot.get("y", 0)))
	var key := _key(tile)
	if not _is_in_farm_area(tile):
		return
	var code: Variant = plot.get("item_code")
	if code == null or str(code) == "":
		var old := get_node_or_null("CropVisual_" + key)
		if old != null:
			remove_child(old)
			old.queue_free()
		active_crops.erase(key)
		if bool(plot.get("is_tilled", false)):
			_draw_soil(tile)
		return
	tilled_tiles[key] = true
	if not active_crops.has(key) or active_crops[key].type != str(code):
		_spawn_crop_visual(tile, str(code))
	var stage := int(plot.get("growth_stage", 0))
	active_crops[key] = {"type": str(code), "stage": GROWTH_STAGES if bool(plot.get("ready", false)) else stage,
		"watered": bool(plot.get("is_watered", false)), "plot_id": int(plot["id"])}
	var visual := get_node_or_null("CropVisual_" + key)
	if visual != null:
		var anim := visual.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		if anim != null:
			anim.set_process(false)
			anim.stop()
			var last_frame := anim.sprite_frames.get_frame_count("default") - 1
			var visual_frame: Variant = plot.get("visual_frame")
			anim.frame = clampi(int(visual_frame) if visual_frame != null else roundi(float(stage) / 3.0 * last_frame), 0, last_frame)


func _relocate(tile: Vector2i) -> void:
	_backend_busy = true
	var version := Global.session_version
	var old_key := _drag_key
	var response: Dictionary = await APIClient.relocate_crop(int(_drag_crop["plot_id"]), tile)
	_backend_busy = false
	_dragging = false
	_drag_key = ""
	_drag_crop = {}
	if version != Global.session_version:
		return
	var visual := get_node_or_null("CropVisual_" + old_key)
	if visual != null:
		visual.global_position = _tile_to_world(_str_to_vec(old_key))
		visual.z_index = VISUAL_Z_INDEX
		var collision := visual.get_node_or_null("StaticBody2D/CollisionShape2D")
		if collision:
			collision.set_deferred("disabled", false)
	if response.get("ok", false):
		var data: Dictionary = APIClient.data_of(response)
		_apply_plot(data["source"])
		_apply_plot(data["plot"])
	else:
		GameState.report_error(response)
	await GameState.refresh_gameplay()
