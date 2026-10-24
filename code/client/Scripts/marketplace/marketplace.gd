extends "res://Scripts/lobby_player_spawner.gd"
## Side-scrolling marketplace.
##
## The general store stands at x = 0. Your own shop takes the first slot on the
## side you chose; friends' shops fill the remaining slots outward. Every layout
## number comes from Assets/marketplace/placement.json, so moving a shop is a
## data change rather than a code change.
##
## Expected scene (Marketplace.tscn):
##   Background/Sprite2D      one panel you positioned by hand; cloned sideways
##   Shops/supershop          empty Sprite2D, textured here
##   Shops/shop#1 … shop#12   empty Sprite2D slots, hidden until needed
##   Camera2D, PlayerSpawn

const DATA := "res://Assets/marketplace/placement.json"
const ART := "res://Assets/marketplace/"
const SHOP_PICKER := preload("res://Scripts/marketplace/shop_picker.gd")
const STORAGE_MENU := preload("res://Scripts/inventory/storage_menu.gd")

const WOOD_COST := 70
const REACH := 140.0      ## how close you stand before a shop is clickable
const BG_PANELS := 5      ## background copies either side of centre

var _spec: Dictionary = {}
var _entries: Dictionary = {}        ## option_id -> placement.json entry
var _shops: Array[Dictionary] = []   ## {node, kind, option_id, name, x, shop_id}
var _slots: Array[Sprite2D] = []     ## the shop#N nodes, in scene order
var _next_slot := 0
var _plot: Node2D = null             ## the "open your shop here" outline
var _near: Dictionary = {}
var _busy := false


# ── setup ────────────────────────────────────────────────────────────────

func _ready() -> void:
	_load_spec()
	$PlayerSpawn.position = Vector2(0, float(_spec["scene"]["walking_y"]))
	_tile_background()
	_collect_slots()
	_place_supershop()
	super._ready()
	await _refresh_shops()


func _load_spec() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	_spec = parsed if parsed is Dictionary else {}
	for entry in _spec.get("shops", []):
		_entries[str(entry["id"])] = entry


func _tile_background() -> void:
	# Clone the panel you placed by hand, so its Y and framing carry over.
	var template := $Background.get_child(0) as Sprite2D
	if template == null:
		return
	var period := float(_spec["background"]["period_x"])
	for i in range(-BG_PANELS, BG_PANELS + 1):
		if i == 0:
			continue
		var copy := template.duplicate() as Sprite2D
		copy.position.x = template.position.x + period * i
		$Background.add_child(copy)


func _collect_slots() -> void:
	for child in $Shops.get_children():
		var sprite := child as Sprite2D
		if sprite == null or sprite.name == "supershop":
			continue
		sprite.visible = false
		_slots.append(sprite)


func _place_supershop() -> void:
	var sprite := $Shops.get_node_or_null("supershop") as Sprite2D
	if sprite == null:
		push_warning("Marketplace: no 'supershop' node under Shops")
		return
	_dress(sprite, "supershop", 0.0, "General Store")
	_shops.append({"node": sprite, "kind": "supershop", "option_id": "supershop",
			"name": "General Store", "x": 0.0, "shop_id": 0})


# ── placing shops ────────────────────────────────────────────────────────

func _dress(sprite: Sprite2D, option_id: String, x: float, label_text: String) -> void:
	var entry: Dictionary = _entries.get(option_id, {})
	if entry.is_empty():
		push_warning("Marketplace: unknown shop option '%s'" % option_id)
		return
	sprite.texture = load(ART + str(entry["file"]))
	sprite.centered = false
	# anchor is the pixel in the image that sits on (x, baseline)
	sprite.offset = -Vector2(float(entry["anchor"][0]), float(entry["anchor"][1]))
	sprite.position = Vector2(x, float(_spec["scene"]["shop_baseline_y"]))
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.visible = true
	_add_name_label(sprite, entry, label_text)


func _add_name_label(sprite: Sprite2D, entry: Dictionary, text: String) -> void:
	var old := sprite.get_node_or_null("ShopName")
	if old:
		old.free()
	if text.is_empty():
		return
	var r: Array = entry["name_text_rect"]     # [x, y, w, h] in image pixels
	var label := Label.new()
	label.name = "ShopName"
	label.text = text
	label.add_theme_font_override("font", WoodPanel.PIXEL_FONT)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color("40291f"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.position = Vector2(float(r[0]), float(r[1])) + sprite.offset
	label.size = Vector2(float(r[2]), float(r[3]))
	sprite.add_child(label)


func _slot_x(side: String, index: int) -> float:
	var scene: Dictionary = _spec["scene"]
	var distance := float(scene["first_neighbor_center_distance"]) \
			+ float(scene["subsequent_shop_center_spacing"]) * index
	return distance if side == "right" else -distance


func _friend_spots(own_side: String, count: int) -> Array:
	# Fill outward from the centre, alternating sides. Slot 0 on your own side
	# is already taken by your shop.
	var used := {"left": 0, "right": 0}
	if own_side != "":
		used[own_side] = 1
	var spots: Array = []
	var turn := 0
	while spots.size() < count:
		var side: String = "left" if turn % 2 == 0 else "right"
		spots.append({"side": side, "index": used[side]})
		used[side] += 1
		turn += 1
	return spots


func _take_slot() -> Sprite2D:
	if _next_slot >= _slots.size():
		return null
	var sprite := _slots[_next_slot]
	_next_slot += 1
	return sprite


func _add_shop(data: Dictionary, side: String, index: int, kind: String) -> void:
	var sprite := _take_slot()
	if sprite == null:
		return     # more shops than slots; the overflow is simply not shown
	var x := _slot_x(side, index)
	var shop_name := str(data.get("name", ""))
	_dress(sprite, str(data["option_id"]), x, shop_name)
	_shops.append({"node": sprite, "kind": kind, "option_id": str(data["option_id"]),
			"name": shop_name, "x": x, "shop_id": int(data.get("id", 0))})


func _place_empty_plot() -> void:
	var baseline := float(_spec["scene"]["shop_baseline_y"])
	_plot = Node2D.new()
	_plot.name = "EmptyPlot"
	_plot.position = Vector2(_slot_x("right", 0), baseline)
	$Shops.add_child(_plot)

	var outline := Line2D.new()
	outline.width = 3.0
	outline.default_color = Color(1, 1, 1, 0.5)
	outline.closed = true
	outline.points = PackedVector2Array([
		Vector2(-116, -182), Vector2(116, -182),
		Vector2(116, 0), Vector2(-116, 0)])
	_plot.add_child(outline)

	var label := Label.new()
	label.text = "Open your shop"
	label.add_theme_font_override("font", WoodPanel.PIXEL_FONT)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-116, -110)
	label.size = Vector2(232, 20)
	_plot.add_child(label)

	_shops.append({"node": _plot, "kind": "empty", "option_id": "",
			"name": "", "x": _plot.position.x, "shop_id": 0})


# ── server sync ──────────────────────────────────────────────────────────

func _refresh_shops() -> void:
	_reset_slots()
	var own := await _fetch_own()
	var own_side := str(own.get("side", "")) if not own.is_empty() else ""
	if not own.is_empty():
		_add_shop(own, own_side, 0, "own")
	var friends := await _fetch_friends()
	var spots := _friend_spots(own_side, friends.size())
	for i in friends.size():
		_add_shop(friends[i], str(spots[i]["side"]), int(spots[i]["index"]), "friend")
	if own.is_empty():
		_place_empty_plot()


func _reset_slots() -> void:
	_shops = _shops.filter(func(s: Dictionary) -> bool: return s["kind"] == "supershop")
	_near = {}
	_next_slot = 0
	for sprite in _slots:
		sprite.visible = false
		var old := sprite.get_node_or_null("ShopName")
		if old:
			old.free()
	if _plot != null and is_instance_valid(_plot):
		_plot.queue_free()
	_plot = null


func _fetch_own() -> Dictionary:
	var response: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_GET, "/market")
	var data: Variant = APIClient.data_of(response)
	return data if data is Dictionary else {}


func _fetch_friends() -> Array:
	var response: Dictionary = await APIClient.authenticated(
			HTTPClient.METHOD_GET, "/market/friends")
	var data: Variant = APIClient.data_of(response)
	return data if data is Array else []


# ── walking and clicking ─────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var band: Array = _spec["scene"]["walkable_y_range"]
	player.global_position.y = clampf(
			player.global_position.y, float(band[0]), float(band[1]))
	_near = {}
	for shop in _shops:
		if absf(player.global_position.x - float(shop["x"])) < REACH:
			_near = shop
			break
	for shop in _shops:
		var node := shop["node"] as CanvasItem
		node.modulate = Color(1.15, 1.15, 1.1) if shop == _near else Color.WHITE


func _unhandled_input(event: InputEvent) -> void:
	if _near.is_empty() or _busy or GameState.menu_open:
		return
	if not (event is InputEventMouseButton and event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if not _hit(_near["node"]):
		return
	get_viewport().set_input_as_handled()
	_open(_near)


func _hit(node: Node2D) -> bool:
	var local := node.to_local(get_global_mouse_position())
	if node is Sprite2D and (node as Sprite2D).texture != null:
		return (node as Sprite2D).get_rect().has_point(local)
	return absf(local.x) < 116.0 and local.y > -182.0 and local.y < 0.0


func _open(shop: Dictionary) -> void:
	match str(shop["kind"]):
		"supershop":
			get_tree().current_scene.add_child(STORAGE_MENU.new())
		"empty":
			_start_open_shop()
		"own":
			_toast("Your shop. Stocking it comes next.")
		"friend":
			_toast("%s. Buying comes next." % str(shop["name"]))


# ── opening your own shop ────────────────────────────────────────────────

func _start_open_shop() -> void:
	if GameState.wood() < WOOD_COST:
		_toast("You need %d wood to open a shop." % WOOD_COST)
		return
	var picker = SHOP_PICKER.new()
	picker.picked.connect(_pick_side)
	get_tree().current_scene.add_child(picker)


func _pick_side(option_id: String) -> void:
	var box := ConfirmationDialog.new()
	box.title = "Where do you want it?"
	box.dialog_text = "Which side of the general store should your shop stand on?"
	box.ok_button_text = "Right side"
	box.add_button("Left side", true, "left")
	box.confirmed.connect(func() -> void: _confirm(option_id, "right"))
	box.custom_action.connect(func(action: StringName) -> void:
		if action == "left":
			box.hide()
			_confirm(option_id, "left"))
	get_tree().current_scene.add_child(box)
	box.popup_centered()


func _confirm(option_id: String, side: String) -> void:
	if _busy:
		return
	_busy = true
	# Spend first so the cost is visible immediately, refund if the server says no.
	if not GameState.spend_wood(WOOD_COST):
		_busy = false
		_toast("You need %d wood to open a shop." % WOOD_COST)
		return
	var shop_name := Global.display_name if Global.display_name != "" else Global.username
	var response: Dictionary = await APIClient.authenticated(
			HTTPClient.METHOD_POST, "/market",
			{"option_id": option_id, "side": side, "name": shop_name + "'s Shop"})
	_busy = false
	if not response.get("ok", false):
		GameState.refund_wood(WOOD_COST)
		_toast(APIClient.error_text(response))
		return
	await _refresh_shops()
	_toast("Your shop is open!")


func _toast(text: String) -> void:
	HousePrompt.flash(text, 3.0)


# ── camera ───────────────────────────────────────────────────────────────

func _fit_camera() -> void:
	# The parent fits the camera to the room's limits. This street has no left
	# or right edge and tight top/bottom limits, which would force a very large
	# zoom, so the configured zoom is kept instead.
	camera.zoom = Vector2.ONE * _preferred_zoom
