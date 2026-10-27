extends Node2D
# Farming controls
#   Left-click a tile (within reach):
#       grass        -> till
#       empty soil   -> open seed picker -> plant
#       dry crop     -> water
#       ripe crop    -> harvest (crop goes to inventory)
#   E on a tile      -> pick the whole tile up (soil + crop)
#   E again          -> put it down on the hovered free spot (or back where it was)
#
# Every tile is two nodes: "Soil_<x>,<y>" underneath and "CropVisual_<x>,<y>" on
# top of it. The soil is never destroyed to make room for a crop.

# ─── Server contract ─────────────────────────────────────────────────

# The server pins the grid at 17 x 21 (farming/service.py: 0 <= x <= 16, 0 <= y <= 20)
const FARM_GRID := Vector2i(17, 21)
const GROWTH_STAGES = 4

# ─── Drawing layers ──────────────────────────────────────────────────

const FARM_Z = 1          # soil tiles
const CROP_Z = 2          # crops, always above their soil
const CURSOR_Z = 50       # hover outline

# ─── Assets ──────────────────────────────────────────────────────────

const SOIL_TEXTURE = preload("res://Assets/farming/soil.png")
const SOIL_REGION = Rect2(408, 106, 605, 556)

# Crop art lives in CROPS: one spritesheet per crop, five growth stages,
# plus the planting point where the stem meets the soil.
const CROP_SCRIPT = preload("res://Scripts/crop_visual.gd")
const CROP_ART = preload("res://Scripts/crop_catalog.gd")

# ─── Tuning (Inspector) ──────────────────────────────────────────────

@export var tile_visual_size: Vector2 = Vector2(50, 50)   # recomputed from the FarmZone on startup
@export var tile_scale: float = 1.0    # 1.0 = biggest tiles that fit the zone; >1 spills past it
@export var tile_gap: float = 2.0      # empty pixels between neighbouring farm tiles
@export var reach_tiles: float = 2.5   # how many tiles away from the player you can click

## Off: square tiles, so the grid fits inside the FarmZone and leaves a margin on
## whichever axis is roomier. On: tiles stretch so the grid fills the zone exactly,
## at the cost of a non-square soil texture.
@export var stretch_to_zone: bool = false

@export var crop_scale: float = 2.2   # how many tile widths one crop frame spans
@export var crop_sink: float = 0.0    # fraction of a tile to push the crop down into the soil

@export var verbose: bool = false     # print farm diagnostics to the console

# ─── Scene ───────────────────────────────────────────────────────────

@onready var farm_layer: TileMapLayer = $"../Map/FarmField/FarmLayer"
@onready var seed_picker = $SeedPickerMenu

# ─── State ───────────────────────────────────────────────────────────

var FARM_AREA_MIN := Vector2.ZERO
var FARM_AREA_MAX := Vector2.ZERO

var active_crops: Dictionary = {}   # "x,y" -> {type, stage, watered, plot_id}
var tilled_tiles: Dictionary = {}   # "x,y" -> true
var _plot_ids: Dictionary = {}      # "x,y" -> server tile id (soil tiles too)

var _pending_tile_pos: Vector2i     # tile waiting on the seed picker
var _pending_key: String
var _backend_busy := false
var _player_in_zone := false

# Carrying a tile (E)
var _dragging := false
var _drag_key := ""
var _drag_crop: Dictionary = {}     # empty = carrying bare soil

var _cursor: Line2D


# ─── Lifecycle ───────────────────────────────────────────────────────

func _ready() -> void:
	_resolve_farm_area()
	_make_cursor()
	_connect_farm_zone()
	seed_picker.seed_selected.connect(_on_seed_selected)
	GameState.farm_updated.connect(_apply_server_plots)
	_apply_server_plots(GameState.farm_plots)


func _process(_delta: float) -> void:
	if _cursor == null:
		return
	var tile := _hover_tile()
	var on_farm := _player_in_zone and _is_in_farm_area(tile) \
		and not GameState.menu_open and not GameState.social_open
	_cursor.visible = on_farm or _dragging
	_cursor.global_position = _tile_to_world(tile)
	if _dragging:
		var ok := _can_drop(tile) or _key(tile) == _drag_key
		_cursor.default_color = Color(0.4, 1, 0.4) if ok else Color(1, 0.3, 0.3)
		# Preview: the carried tile snaps to the hovered square
		var spot := _tile_to_world(tile) if _is_in_farm_area(tile) else get_global_mouse_position()
		for node in _carried_nodes(_drag_key):
			_place(node, spot)
	elif on_farm:
		_cursor.default_color = Color(1, 1, 1, 0.9) if _in_reach(tile) else Color(1, 0.3, 0.3, 0.7)


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


func _blocked() -> bool:
	return not _player_in_zone or GameState.menu_open or GameState.social_open or _backend_busy \
		or (Global.is_logged_in() and not GameState.backend_ready)


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


# ─── Farm area and zone ──────────────────────────────────────────────

func _resolve_farm_area() -> void:
	# The farm is centred inside the FarmZone rectangle. Resize that shape in the
	# editor and the grid follows - nothing here needs touching.
	var shape := get_node_or_null("../Map/FarmField/FarmZone/CollisionShape2D") as CollisionShape2D
	if shape == null or not (shape.shape is RectangleShape2D):
		push_warning("FarmZone rectangle missing - farm area not placed")
		return
	var zone_px: Vector2 = (shape.shape as RectangleShape2D).size * shape.global_scale
	var per_tile := Vector2(zone_px.x / FARM_GRID.x, zone_px.y / FARM_GRID.y) * tile_scale
	if stretch_to_zone:
		# Fill the zone exactly; tiles stop being square if the zone is not 17:21.
		tile_visual_size = per_tile
	else:
		# Square tiles: take whichever axis is tighter, so the grid fits inside the
		# zone rather than stretching to it. Keeps the soil texture undistorted.
		var t: float = minf(per_tile.x, per_tile.y)
		tile_visual_size = Vector2(t, t)
	var grid_px := Vector2(FARM_GRID) * tile_visual_size
	FARM_AREA_MIN = shape.global_position - grid_px * 0.5
	FARM_AREA_MAX = FARM_AREA_MIN + grid_px
	_diag("farm area %s .. %s  tile=%s  zone=%s" % [FARM_AREA_MIN, FARM_AREA_MAX, tile_visual_size, zone_px])


func _connect_farm_zone() -> void:
	var zone := get_node_or_null("../Map/FarmField/FarmZone") as Area2D
	if zone == null:
		push_warning("FarmZone missing - farming stays locked")
		return
	zone.body_entered.connect(_on_zone_entered)
	zone.body_exited.connect(_on_zone_exited)
	_check_zone_at_start(zone)


func _check_zone_at_start(zone: Area2D) -> void:
	# Area2D only fires when you CROSS the edge - a player who spawns inside
	# never triggers it, so check for an overlap once on startup.
	await get_tree().physics_frame
	for body in zone.get_overlapping_bodies():
		if body.is_in_group("player"):
			_player_in_zone = true


func _on_zone_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_zone = true


func _on_zone_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_zone = false
		if _cursor != null:
			_cursor.visible = false


# ─── Farming actions ─────────────────────────────────────────────────

func _till(tile_pos: Vector2i) -> void:
	if Global.is_logged_in():
		await _server_action("till", tile_pos, _key(tile_pos))
		return
	AudioManager.play("till")
	_draw_soil(tile_pos)


func _plant(tile_pos: Vector2i, key: String) -> void:
	_pending_tile_pos = tile_pos
	_pending_key = key
	seed_picker.show_menu()


func _on_seed_selected(seed_name: String) -> void:
	if Global.is_logged_in():
		await _server_action("plant", _pending_tile_pos, _pending_key, seed_name)
		return
	AudioManager.play("plant")
	GameState.seed_inventory[seed_name] = int(GameState.seed_inventory.get(seed_name, 0)) - 1
	GameState.seed_changed.emit(seed_name)
	active_crops[_pending_key] = {"type": seed_name, "stage": 0, "watered": false}
	_spawn_crop_visual(_pending_tile_pos, seed_name)


func _water(tile_pos: Vector2i, key: String) -> void:
	if Global.is_logged_in():
		await _server_action("water", tile_pos, key)
		return
	if not GameState.spend_water(1):
		_toast("No water - refill at the pond (Q)", tile_pos)
		return
	AudioManager.play("water_crop")
	active_crops[key].watered = true
	var anim = get_node_or_null("CropVisual_" + key + "/AnimatedSprite2D")
	if anim:
		anim.water()


func _harvest(tile_pos: Vector2i, key: String) -> void:
	if Global.is_logged_in():
		await _server_action("harvest", tile_pos, key)
		return
	AudioManager.play("harvest")
	var crop_type: String = active_crops[key].type
	_remove_crop_visual(key)
	active_crops.erase(key)
	_remove_soil(key)  # harvest clears the tile back to grass
	GameState.add_item_offline(crop_type, crop_type.capitalize(), 1)
	_toast("+1 %s -> Inventory" % crop_type.capitalize(), tile_pos)


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
	# Offline: just move the nodes and the dictionaries. The carried tile brings
	# its own soil, so any soil already on the target square is replaced.
	if not _drag_crop.is_empty():
		var under := get_node_or_null("Soil_" + key)
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
		node.z_index = CROP_Z if _is_crop_node(node) else FARM_Z


# ─── Visuals ─────────────────────────────────────────────────────────

# size a tile is DRAWN at (slightly smaller than the grid cell, so a gap shows)
func _drawn_size() -> Vector2:
	return tile_visual_size - Vector2(tile_gap, tile_gap)


func _is_crop_node(node: Node) -> bool:
	return str(node.name).begins_with("CropVisual_")


# ColorRect placeholders sit by their top-left corner, sprites by their centre,
# and a crop by the point where its stem meets the soil.
func _place(node: Node, center: Vector2) -> void:
	if node is Control:
		node.global_position = center - node.size / 2.0
	elif _is_crop_node(node):
		node.global_position = _crop_anchor(center)
	else:
		node.global_position = center


func _crop_anchor(center: Vector2) -> Vector2:
	# Where the base of the plant lands on its soil tile.
	return center + Vector2(0.0, _drawn_size().y * crop_sink)


func _draw_soil(tile_pos: Vector2i) -> void:
	var key := _key(tile_pos)
	tilled_tiles[key] = true
	if get_node_or_null("Soil_" + key) != null:
		return
	var soil := Sprite2D.new()
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
	var key := _key(tile_pos)
	_remove_crop_visual(key)
	_draw_soil(tile_pos)   # the soil stays put; everything else goes on top of it

	# One row of growth stages, sliced into an AnimatedSprite2D so the growth,
	# watering and server-frame code all keep working unchanged.
	var sprite_frames := CROP_ART.sprite_frames(crop_type)
	if sprite_frames == null:
		push_warning("no spritesheet for crop '%s' - drawing a placeholder" % crop_type)
		_spawn_crop_placeholder(tile_pos, key)
		return
	var frame_size := CROP_ART.frame_size(crop_type)
	var plant_point := CROP_ART.planting_point(crop_type)

	var anim := AnimatedSprite2D.new()
	anim.name = "AnimatedSprite2D"
	anim.set_script(CROP_SCRIPT)
	anim.sprite_frames = sprite_frames
	anim.centered = false
	# Shift the art so the parent's origin sits exactly on the planting point.
	# Put that origin on the soil and the plant stands on it at any growth stage.
	anim.position = -plant_point

	var node := Node2D.new()
	node.name = "CropVisual_" + key
	node.z_index = CROP_Z
	var s: float = _drawn_size().x * crop_scale / maxf(frame_size.x, 1.0)
	node.scale = Vector2(s, s)
	node.add_child(anim)
	add_child(node)
	node.global_position = _crop_anchor(_tile_to_world(tile_pos))
	anim.fully_grown.connect(_on_crop_fully_grown.bind(node), CONNECT_ONE_SHOT)


func _spawn_crop_placeholder(tile_pos: Vector2i, key: String) -> void:
	var size := _drawn_size()
	var rect := ColorRect.new()
	rect.name = "CropVisual_" + key
	rect.size = size
	rect.position = -size / 2.0
	rect.color = Color(0.6, 0.8, 0.4)
	rect.z_index = CROP_Z
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE  # don't eat clicks
	add_child(rect)
	rect.global_position = _tile_to_world(tile_pos) - size / 2.0


func _on_crop_fully_grown(node: Node) -> void:
	if Global.is_logged_in():
		return
	var key := str(node.name).trim_prefix("CropVisual_")  # works even after the tile was moved
	if active_crops.has(key):
		active_crops[key].stage = GROWTH_STAGES


func _make_cursor() -> void:
	_cursor = Line2D.new()
	_cursor.name = "HoverCursor"
	_cursor.width = 3.0
	_cursor.closed = true
	_cursor.z_index = CURSOR_Z
	var h := tile_visual_size / 2.0
	_cursor.points = PackedVector2Array([
		Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)])
	_cursor.visible = false
	add_child(_cursor)


## Farm feedback goes on the message line, not floating over the tile. It is
## frequent (every click), so it stays silent.
func _toast(text: String, _tile: Vector2i) -> void:
	HousePrompt.flash(text, 2.0, false)


# ─── Tile math ───────────────────────────────────────────────────────

func _hover_tile() -> Vector2i:
	return _get_tile_pos(get_global_mouse_position())


func _get_tile_pos(global_pos: Vector2) -> Vector2i:
	var rel := global_pos - FARM_AREA_MIN
	return Vector2i(floori(rel.x / tile_visual_size.x), floori(rel.y / tile_visual_size.y))


func _tile_to_world(tile_pos: Vector2i) -> Vector2:
	return FARM_AREA_MIN + Vector2(
		(tile_pos.x + 0.5) * tile_visual_size.x,
		(tile_pos.y + 0.5) * tile_visual_size.y)


func _is_in_farm_area(tile_pos: Vector2i) -> bool:
	var center := _tile_to_world(tile_pos)
	return center.x >= FARM_AREA_MIN.x and center.x <= FARM_AREA_MAX.x \
		and center.y >= FARM_AREA_MIN.y and center.y <= FARM_AREA_MAX.y


func _in_reach(tile: Vector2i) -> bool:
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return false
	return player.global_position.distance_to(_tile_to_world(tile)) <= reach_tiles * tile_visual_size.x


func _key(tile: Vector2i) -> String:
	return "%d,%d" % [tile.x, tile.y]


func _str_to_vec(s: String) -> Vector2i:
	var parts := s.split(",")
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
		AudioManager.play("water_crop" if action == "water" else action)
		var data: Variant = APIClient.data_of(response)
		if data is Dictionary:
			_apply_plot(data.get("plot", data))
			if action == "harvest":
				var code := str(data.get("item_code", "crop"))
				_toast("+%d %s -> Inventory" % [int(data.get("quantity", 1)), code.capitalize()], tile)
	else:
		_toast(APIClient.error_text(response), tile)
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
	_plot_ids[key] = int(plot.get("id", 0))

	var code: Variant = plot.get("item_code")
	if code == null or str(code) == "":
		# Bare tile: soil only, or nothing at all if it was carried away.
		_remove_crop_visual(key)
		active_crops.erase(key)
		if bool(plot.get("is_tilled", false)):
			_draw_soil(tile)
		else:
			_remove_soil(key)
		return

	tilled_tiles[key] = true
	_draw_soil(tile)   # a planted tile always shows its soil
	if not active_crops.has(key) or active_crops[key].type != str(code):
		_spawn_crop_visual(tile, str(code))

	var stage := int(plot.get("growth_stage", 0))
	active_crops[key] = {
		"type": str(code),
		"stage": GROWTH_STAGES if bool(plot.get("ready", false)) else stage,
		"watered": bool(plot.get("is_watered", false)),
		"plot_id": int(plot["id"]),
	}
	# The server owns the growth stage, so freeze the local animation on its frame.
	var anim := get_node_or_null("CropVisual_" + key + "/AnimatedSprite2D") as AnimatedSprite2D
	if anim != null:
		anim.set_process(false)
		anim.stop()
		var last_frame := anim.sprite_frames.get_frame_count("default") - 1
		var visual_frame: Variant = plot.get("visual_frame")
		var wanted := int(visual_frame) if visual_frame != null else roundi(float(stage) / 3.0 * last_frame)
		anim.frame = clampi(wanted, 0, last_frame)


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


# ─── Diagnostics ─────────────────────────────────────────────────────

func _diag(msg: String) -> void:
	if verbose:
		print("[FARMDIAG] %s" % msg)
