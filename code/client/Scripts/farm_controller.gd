extends Node2D
# Farming controls
#   Left-click a tile (within reach):
#       grass        -> till
#       empty soil   -> open seed picker -> plant
#       dry crop     -> water
#       ripe crop    -> harvest (crop goes to inventory)
#   E on a tile      -> pick the whole tile up (soil + crop)
#   E again          -> put it down on the hovered free spot (or back where it was)

@onready var farm_layer: TileMapLayer = $"../Map/FarmLayer"
@onready var seed_picker = $SeedPickerMenu

const FARM_AREA_MIN := Vector2(8629.15, -3797.821)
const FARM_AREA_MAX := Vector2(11129.43, -693.0)
const GROWTH_STAGES = 4
const FARM_Z = 1          # every farm tile (soil and crop) is drawn on this z_index
const CURSOR_Z = 50

@export var tile_visual_size: Vector2 = Vector2(50, 50)
@export var reach_tiles: float = 2.5   # how many tiles away from the player you can click
@export var tile_gap: float = 2.0      # empty pixels between neighbouring farm tiles

const SOIL_TEXTURE = preload("res://Assets/farming/soil.png")
const SOIL_REGION = Rect2(408, 106, 605, 556)

var active_crops: Dictionary = {}   # "x,y" -> {type, stage, watered, plot_id}
var tilled_tiles: Dictionary = {}   # "x,y" -> true
var _plot_ids: Dictionary = {}      # "x,y" -> server tile id (soil tiles too)

var _pending_tile_pos: Vector2i
var _pending_key: String
var _backend_busy := false

# Carrying a tile (E)
var _dragging := false
var _drag_key := ""
var _drag_crop: Dictionary = {}     # empty = carrying bare soil

var _cursor: Line2D

var _player_in_zone := false

func _get_tile_visual_size() -> Vector2:
	return tile_visual_size

func _connect_farm_zone() -> void:
	var zone := get_node_or_null("../Map/FarmField/FarmZone") as Area2D
	if zone == null:
		push_warning("FarmZone missing — farming stays locked")
		return
	zone.body_entered.connect(_on_zone_entered)
	zone.body_exited.connect(_on_zone_exited)
	_check_zone_at_start(zone)


func _check_zone_at_start(zone: Area2D) -> void:
	# Area2D only fires when you CROSS the edge — a player who spawns inside
	# never triggers it, so check for an overlap once on startup.
	await get_tree().physics_frame
	for body in zone.get_overlapping_bodies():
		if body.is_in_group("player"):
			_player_in_zone = true


func _on_zone_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_zone = true
		_diag("entered farm zone")


func _on_zone_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_zone = false
		_cursor.visible = false

# size a tile is DRAWN at (slightly smaller than the grid cell, so a gap shows)
func _drawn_size() -> Vector2:
	return tile_visual_size - Vector2(tile_gap, tile_gap)


func _ready():
	print("=== FARM CONTROLLER READY ===")
	print("FarmLayer exists: ", farm_layer != null)
	if farm_layer:
		print("FarmLayer tile_set exists: ", farm_layer.tile_set != null)
	seed_picker.seed_selected.connect(_on_seed_selected)
	_diag("seed_picker connected")
	_make_cursor()
	GameState.farm_updated.connect(_apply_server_plots)
	_make_cursor()   # the hover outline; _process() uses it every frame
	_apply_server_plots(GameState.farm_plots)
	_diag("apply_server_plots returned")


func _diag(msg: String) -> void:
	print("[FARMDIAG] %s" % msg)


func _diag_dump_plots(plots: Array) -> void:
	_diag("plots is Array=%s size=%d" % [plots is Array, plots.size()])
	if plots.is_empty():
		return
	var xs := []
	var ys := []
	var keys := {}
	var bad := 0
	for plot in plots:
		if not (plot is Dictionary):
			bad += 1
			continue
		var px := int(plot.get("x", 0))
		var py := int(plot.get("y", 0))
		xs.append(px)
		ys.append(py)
		for k in plot.keys():
			keys[k] = true
		if not _is_in_farm_area(Vector2i(px, py)):
			bad += 1
	if not xs.is_empty():
		_diag("x range=[%d..%d] y range=[%d..%d] outside_farm_area=%d" % [
			xs.min(), xs.max(), ys.min(), ys.max(), bad])
	_diag("plot keys=%s" % str(keys.keys()))


# ─── Input ───────────────────────────────────────────────────────────

func _blocked() -> bool:
	return not _player_in_zone or GameState.menu_open or GameState.social_open or _backend_busy \
		or (Global.is_logged_in() and not GameState.backend_ready)

func _unhandled_input(event: InputEvent) -> void:
	if _blocked():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _dragging:
			return  # carrying: only E puts the tile down
		if _is_in_farm_area(_hover_tile()):
			get_viewport().set_input_as_handled()
			_on_click(_hover_tile())
	elif event.is_action_pressed("interact"):
		if _dragging:
			get_viewport().set_input_as_handled()
			_drop(_hover_tile())
		elif _is_in_farm_area(_hover_tile()):
			get_viewport().set_input_as_handled()
			_pick_up(_hover_tile())



func _on_click(tile: Vector2i) -> void:
	if not _in_reach(tile):
		_toast("Too far away", tile)
		return
	var key := _key(tile)
	if not tilled_tiles.has(key):
		_till(tile)
	elif not active_crops.has(key):
		_plant(tile, key)
	else:
		var crop: Dictionary = active_crops[key]
		if crop.stage >= GROWTH_STAGES:
			_harvest(tile, key)
		elif not crop.watered:
			_water(tile, key)
		else:
			_toast("Growing...", tile)


# ─── Hover cursor ────────────────────────────────────────────────────

func _make_cursor() -> void:
	_cursor = Line2D.new()
	_cursor.name = "HoverCursor"
	_cursor.width = 3.0
	_cursor.closed = true
	_cursor.z_index = CURSOR_Z
	var h := tile_visual_size / 2.0
	_cursor.points = PackedVector2Array([Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)])
	_cursor.visible = false
	add_child(_cursor)


func _process(_delta):
	if _cursor == null:
		return
	var tile := _hover_tile()
	var on_farm := _player_in_zone and _is_in_farm_area(tile) and not GameState.menu_open and not GameState.social_open
	_cursor.visible = on_farm or _dragging
	_cursor.global_position = _tile_to_world(tile)
	if _dragging:
		_cursor.default_color = Color(0.4, 1, 0.4) if _can_drop(tile) or _key(tile) == _drag_key else Color(1, 0.3, 0.3)
		# Preview: the carried tile snaps to the hovered square
		var spot := _tile_to_world(tile) if _is_in_farm_area(tile) else get_global_mouse_position()
		for node in _carried_nodes(_drag_key):
			_place(node, spot)
	elif on_farm:
		_cursor.default_color = Color(1, 1, 1, 0.9) if _in_reach(tile) else Color(1, 0.3, 0.3, 0.7)


# ─── Carrying a whole tile (E) ───────────────────────────────────────

func _pick_up(tile: Vector2i) -> void:
	var key := _key(tile)
	if not tilled_tiles.has(key):
		return
	if not _in_reach(tile):
		_toast("Too far away", tile)
		return
	_dragging = true
	_drag_key = key
	_drag_crop = active_crops.get(key, {}).duplicate()
	_set_carry_look(key, true)


func _drop(tile: Vector2i) -> void:
	var key := _key(tile)
	if key == _drag_key:
		_end_carry()  # put it back where it was
		return
	if not _can_drop(tile):
		_toast("Can't put it here", tile)
		return
	if Global.is_logged_in():
		await _relocate(tile)
		return
	# Offline: just move the nodes and the dictionaries
	if not _drag_crop.is_empty():
		var under := get_node_or_null("Soil_" + key)  # crop covers the soil it lands on
		if under:
			remove_child(under)
			under.queue_free()
	for node in _carried_nodes(_drag_key):
		node.name = str(node.name).get_slice("_", 0) + "_" + key
	tilled_tiles.erase(_drag_key)
	tilled_tiles[key] = true
	if active_crops.has(_drag_key):
		active_crops[key] = active_crops[_drag_key]
		active_crops.erase(_drag_key)
	_drag_key = key
	_end_carry()


func _can_drop(tile: Vector2i) -> bool:
	var key := _key(tile)
	if not _is_in_farm_area(tile) or not _in_reach(tile) or active_crops.has(key):
		return false
	# a crop may land on empty soil; bare soil may only land on grass
	return not _drag_crop.is_empty() or not tilled_tiles.has(key)


func _end_carry() -> void:
	for node in _carried_nodes(_drag_key):
		_place(node, _tile_to_world(_str_to_vec(_drag_key)))
	_set_carry_look(_drag_key, false)
	_dragging = false
	_drag_key = ""
	_drag_crop = {}


# ColorRect placeholders are positioned by their top-left corner, sprites by their centre
func _place(node: Node, center: Vector2) -> void:
	if node is Control:
		node.global_position = center - node.size / 2.0
	else:
		node.global_position = center


func _carried_nodes(key: String) -> Array:
	var nodes := []
	for n in ["Soil_" + key, "CropVisual_" + key]:
		var node := get_node_or_null(n)
		if node != null:
			nodes.append(node)
	return nodes


func _set_carry_look(key: String, carrying: bool) -> void:
	for node in _carried_nodes(key):
		node.modulate.a = 0.6 if carrying else 1.0
		node.z_index = FARM_Z
		var shape = node.get_node_or_null("StaticBody2D/CollisionShape2D")
		if shape:
			shape.set_deferred("disabled", carrying)


# ─── Farming actions ─────────────────────────────────────────────────

func _till(tile_pos: Vector2i):
	if Global.is_logged_in():
		await _server_action("till", tile_pos, _key(tile_pos))
		return
	_draw_soil(tile_pos)


func _plant(tile_pos: Vector2i, key: String):
	_pending_tile_pos = tile_pos
	_pending_key = key
	seed_picker.show_menu()


func _on_seed_selected(seed_name: String) -> void:
	if Global.is_logged_in():
		await _server_action("plant", _pending_tile_pos, _pending_key, seed_name)
		return
	GameState.seed_inventory[seed_name] = int(GameState.seed_inventory.get(seed_name, 0)) - 1
	GameState.seed_changed.emit(seed_name)
	active_crops[_pending_key] = {"type": seed_name, "stage": 0, "watered": false}
	_spawn_crop_visual(_pending_tile_pos, seed_name)


func _water(tile_pos: Vector2i, key: String):
	if Global.is_logged_in():
		await _server_action("water", tile_pos, key)
		return
	if not GameState.spend_water(1):
		_toast("No water - refill at the pond (Q)", tile_pos)
		return
	active_crops[key].watered = true
	var anim = get_node_or_null("CropVisual_" + key + "/AnimatedSprite2D")
	if anim:
		anim.water()


func _harvest(tile_pos: Vector2i, key: String):
	if Global.is_logged_in():
		await _server_action("harvest", tile_pos, key)
		return
	var crop_type: String = active_crops[key].type
	_remove_crop_visual(key)
	active_crops.erase(key)
	_remove_soil(key)  # harvest clears the tile back to grass
	GameState.add_item_offline(crop_type, crop_type.capitalize(), 1)  # actually store it
	_toast("+1 %s → Inventory" % crop_type.capitalize(), tile_pos)


# ─── Visuals ─────────────────────────────────────────────────────────

func _draw_soil(tile_pos: Vector2i):
	var key = _key(tile_pos)
	tilled_tiles[key] = true
	if get_node_or_null("Soil_" + key) != null or get_node_or_null("CropVisual_" + key) != null:
		return
	var soil = Sprite2D.new()
	soil.name = "Soil_" + key
	soil.texture = SOIL_TEXTURE
	soil.region_enabled = true
	soil.region_rect = SOIL_REGION
	soil.centered = true
	soil.z_index = FARM_Z
	soil.scale = _drawn_size() / Vector2(SOIL_REGION.size)
	add_child(soil)
	soil.global_position = _tile_to_world(tile_pos)


func _remove_soil(key: String) -> void:
	tilled_tiles.erase(key)
	var soil := get_node_or_null("Soil_" + key)
	if soil:
		remove_child(soil)
		soil.queue_free()


func _remove_crop_visual(key: String) -> void:
	var old := get_node_or_null("CropVisual_" + key)
	if old:
		remove_child(old)
		old.queue_free()


func _spawn_crop_visual(tile_pos: Vector2i, crop_type: String) -> void:
	var key = _key(tile_pos)
	_remove_crop_visual(key)
	var soil = get_node_or_null("Soil_" + key)
	if soil:
		remove_child(soil)
		soil.queue_free()
	var path = "res://Scenes/crops/%s.tscn" % crop_type
	if not ResourceLoader.exists(path):
		var size = _drawn_size()
		var rect = ColorRect.new()
		rect.name = "CropVisual_" + key
		rect.size = size
		rect.position = -size / 2.0
		rect.color = Color(0.6, 0.8, 0.4)
		rect.z_index = FARM_Z
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE  # don't eat clicks
		add_child(rect)
		rect.global_position = _tile_to_world(tile_pos) - size / 2.0
		return
	var node: Node = load(path).instantiate()
	node.name = "CropVisual_" + key
	node.z_index = FARM_Z
	add_child(node)
	node.global_position = _tile_to_world(tile_pos)
	var anim = node.get_node_or_null("AnimatedSprite2D")
	if anim:
		anim.fully_grown.connect(_on_crop_fully_grown.bind(node), CONNECT_ONE_SHOT)
		var frame_tex = anim.sprite_frames.get_frame_texture("default", 0)
		if frame_tex:
			var frame_size = frame_tex.get_size()
			if frame_size.x > 0 and frame_size.y > 0 and anim.scale.x > 0:
				node.scale = 1.5 * _drawn_size() / (frame_size * anim.scale)


func _on_crop_fully_grown(node: Node) -> void:
	if Global.is_logged_in():
		return
	var key := str(node.name).trim_prefix("CropVisual_")  # works even after the tile was moved
	if active_crops.has(key):
		active_crops[key].stage = GROWTH_STAGES


func _toast(text: String, tile: Vector2i) -> void:
	var label := Label.new()
	label.text = text
	label.z_index = CURSOR_Z
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	add_child(label)
	label.global_position = _tile_to_world(tile) + Vector2(-60, -tile_visual_size.y)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 50, 1.2)
	tween.tween_property(label, "modulate:a", 0.0, 1.2)
	tween.chain().tween_callback(label.queue_free)


# ─── Tile math ───────────────────────────────────────────────────────

func _hover_tile() -> Vector2i:
	return _get_tile_pos(get_global_mouse_position())


func _in_reach(tile: Vector2i) -> bool:
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return false
	return player.global_position.distance_to(_tile_to_world(tile)) <= reach_tiles * tile_visual_size.x


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
	return FARM_AREA_MIN + Vector2((tile_pos.x + 0.5) * size.x, (tile_pos.y + 0.5) * size.y)


func _key(tile: Vector2i) -> String:
	return "%d,%d" % [tile.x, tile.y]


func _str_to_vec(s: String) -> Vector2i:
	var parts = s.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))


# ─── Server sync ─────────────────────────────────────────────────────

func _server_action(action: String, tile: Vector2i, key: String, seed: String = "") -> void:
	# Every persistent farm write funnels through here, so a visitor standing in
	# someone else's world is stopped in one place instead of at each control.
	# The server refuses these too; this only avoids a pointless round trip and
	# an error popup for an action the player is not allowed to make.
	if GameState.read_only:
		GameState.report_error({"body": {"message": "You are visiting this farm and cannot change it."}})
		return
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
			_apply_plot(data.get("plot", data))
			if action == "harvest":
				var code := str(data.get("item_code", "crop"))
				_toast("+%d %s → Inventory" % [int(data.get("quantity", 1)), code.capitalize()], tile)
	else:
		_toast(APIClient.error_text(response), tile)
		GameState.report_error(response)
	await GameState.refresh_gameplay()


func _apply_server_plots(plots: Array) -> void:
	if _backend_busy or _dragging:
		return
	for plot in plots:
		_diag("applying plot %s" % str(plot))
		_apply_plot(plot)


func _apply_plot(plot: Dictionary) -> void:
	var tile := Vector2i(int(plot.get("x", 0)), int(plot.get("y", 0)))
	var key := _key(tile)
	if not _is_in_farm_area(tile):
		return
	_plot_ids[key] = int(plot.get("id", 0))
	var code: Variant = plot.get("item_code")
	if code == null or str(code) == "":
		_remove_crop_visual(key)
		active_crops.erase(key)
		if bool(plot.get("is_tilled", false)):
			_draw_soil(tile)
		else:
			_remove_soil(key)  # tile was moved away -> back to grass
		return
	tilled_tiles[key] = true
	if not active_crops.has(key) or active_crops[key].type != str(code):
		_diag("spawn crop visual key=%s code=%s" % [key, str(code)])
		_spawn_crop_visual(tile, str(code))
	var stage := int(plot.get("growth_stage", 0))
	active_crops[key] = {"type": str(code), "stage": GROWTH_STAGES if bool(plot.get("ready", false)) else stage,
		"watered": bool(plot.get("is_watered", false)), "plot_id": int(plot["id"])}
	var anim := get_node_or_null("CropVisual_" + key + "/AnimatedSprite2D") as AnimatedSprite2D
	if anim != null:
		anim.set_process(false)
		anim.stop()
		var last_frame := anim.sprite_frames.get_frame_count("default") - 1
		var visual_frame: Variant = plot.get("visual_frame")
		anim.frame = clampi(int(visual_frame) if visual_frame != null else roundi(float(stage) / 3.0 * last_frame), 0, last_frame)


func _relocate(tile: Vector2i) -> void:
	# Relocate writes to the host's tiles too, so it is gated like every other
	# farm mutation rather than trusted because it starts from a drag gesture.
	if GameState.read_only:
		GameState.report_error({"body": {"message": "You are visiting this farm and cannot change it."}})
		return
	_backend_busy = true
	var version := Global.session_version
	var plot_id := int(_plot_ids.get(_drag_key, _drag_crop.get("plot_id", 0)))
	var response: Dictionary = await APIClient.relocate_crop(plot_id, tile)
	_backend_busy = false
	if version != Global.session_version:
		return
	_end_carry()  # snap visuals back; the server answer redraws both tiles
	if response.get("ok", false):
		var data: Dictionary = APIClient.data_of(response)
		_apply_plot(data["source"])
		_apply_plot(data["plot"])
	else:
		_toast(APIClient.error_text(response), tile)
		GameState.report_error(response)
	await GameState.refresh_gameplay()
