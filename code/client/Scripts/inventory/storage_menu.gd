extends CanvasLayer
# Storage house menu (opened by clicking the CDS building).
#
#  ROOM VIEW  - inventory.png in the middle of the screen with 4 clickable spots:
#               crops (crates + barrel), seeds (shelf), fish (aquarium), misc (left crates)
#               The aquarium shows up to 5 of the fish you have caught, swimming around.
#  SECTION VIEW - slots for that section on the left, details of the clicked item on the
#               right (icon, description, price) with Sell / Buy buttons under them.
#  Esc: section -> room -> closed.

signal closed

const ROOM_TEXTURE := preload("res://Assets/inventory/inventory.png")
const ROOM_SIZE := Vector2(1619, 971)   # inventory.png size in pixels

# clickable spots, in inventory.png pixels
const SECTIONS := {
	"crops": {"title": "Crops", "rect": Rect2(1210, 530, 409, 330)},
	"seeds": {"title": "Seeds", "rect": Rect2(1210, 280, 375, 235)},
	"fish": {"title": "Fish Tank", "rect": Rect2(516, 320, 544, 250)},
	"misc": {"title": "Miscellaneous", "rect": Rect2(0, 505, 500, 395)},
}
const TANK := Rect2(530, 340, 515, 215)   # water inside the aquarium, where fish swim
const MAX_FISH_SHOWN := 5
const SEASONS := ["summer", "autumn", "winter", "spring"]   # same order as weather_manager.gd

# where bought items go in the offline bag: section -> [partition, category]
const OFFLINE_KIND := {"crops": ["crops", "crop"], "seeds": ["seeds", "seed"], "fish": ["fish", "fish"], "misc": ["tools", "misc"]}

var _scale := 1.0
var _room: TextureRect
var _tank: Control
var _section_view: PanelContainer
var _section := ""          # open section ("" = room view)
var _selected := ""         # selected item code
var _busy := false

# section view widgets
var _title: Label
var _aura: Label
var _grid: GridContainer
var _icon: TextureRect
var _name: Label
var _info: Label
var _desc: Label
var _price: Label
var _status: Label
var _sell: Button
var _buy: Button


func _ready() -> void:
	layer = 20
	GameState.menu_open = true   # freezes the player and farm clicks while the menu is open
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = WoodPanel.make_overlay_color()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	_build_room(root)
	_build_section_view(root)
	_show_room()
	GameState.inventory_updated.connect(func(_items: Array) -> void: _refresh())
	GameState.economy_updated.connect(func(_data: Dictionary) -> void: _refresh())


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _section != "":
			_show_room()
		else:
			close()


func close() -> void:
	GameState.menu_open = false
	closed.emit()
	queue_free()


# ─── Room view (inventory.png) ───────────────────────────────────────

func _build_room(root: Control) -> void:
	var screen := get_viewport().get_visible_rect().size
	_scale = minf(screen.x * 0.9 / ROOM_SIZE.x, screen.y * 0.9 / ROOM_SIZE.y)
	_room = TextureRect.new()
	_room.texture = ROOM_TEXTURE
	_room.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_room.stretch_mode = TextureRect.STRETCH_SCALE
	_room.size = ROOM_SIZE * _scale
	_room.position = (screen - _room.size) / 2.0
	root.add_child(_room)

	_tank = Control.new()
	_tank.clip_contents = true
	_tank.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tank.position = TANK.position * _scale
	_tank.size = TANK.size * _scale
	_room.add_child(_tank)

	for key in SECTIONS:
		_room.add_child(_make_hotspot(key))

	var hint := _label("Click a shelf, the crates or the fish tank", WoodPanel.SIZE_STATUS)
	hint.position = Vector2(0, _room.size.y - 44)
	hint.size = Vector2(_room.size.x, 36)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_room.add_child(hint)

	var x := _button("X")
	x.position = Vector2(_room.size.x - 60, 12)
	x.pressed.connect(close)
	_room.add_child(x)


# invisible button over one part of the picture; gold outline + name when hovered
func _make_hotspot(key: String) -> Button:
	var rect: Rect2 = SECTIONS[key]["rect"]
	var spot := Button.new()
	spot.position = rect.position * _scale
	spot.size = rect.size * _scale
	spot.tooltip_text = SECTIONS[key]["title"]
	spot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(1, 0.95, 0.7, 0.12)
	hover.border_color = Color(1.0, 0.84, 0.0)
	hover.set_border_width_all(3)
	hover.set_corner_radius_all(10)
	for state in ["normal", "focus", "disabled"]:
		spot.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	spot.add_theme_stylebox_override("hover", hover)
	spot.add_theme_stylebox_override("pressed", hover)
	var tag := _label(SECTIONS[key]["title"], WoodPanel.SIZE_CARD_NAME)
	tag.size = Vector2(spot.size.x, 32)
	tag.position = Vector2(0, 6)
	tag.visible = false
	spot.add_child(tag)
	spot.mouse_entered.connect(func() -> void: tag.visible = true)
	spot.mouse_exited.connect(func() -> void: tag.visible = false)
	spot.pressed.connect(_open_section.bind(key))
	return spot


func _show_room() -> void:
	_section = ""
	_selected = ""
	_section_view.visible = false
	_room.visible = true
	_spawn_fish()


# up to 5 different fish you own, swimming in the aquarium
func _spawn_fish() -> void:
	for child in _tank.get_children():
		child.queue_free()
	var codes := []
	for row in _rows_in("fish"):
		if codes.size() < MAX_FISH_SHOWN:
			codes.append(row["code"])
	if codes.is_empty():
		var empty := _label("No fish yet - catch some at the lake!", WoodPanel.SIZE_SMALL)
		empty.size = _tank.size
		_tank.add_child(empty)
		return
	var h := _tank.size.y * 0.24
	for code in codes:
		var fish := TextureRect.new()
		fish.texture = _icon_for(code)
		fish.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fish.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		fish.size = Vector2(h * 1.4, h)
		fish.position = _random_tank_spot(fish.size)
		fish.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tank.add_child(fish)
		_swim(fish)


func _swim(fish: TextureRect) -> void:
	if not is_instance_valid(fish):
		return
	var to := _random_tank_spot(fish.size)
	fish.flip_h = to.x < fish.position.x   # face the way it swims (swap < to > if they swim backwards)
	var speed := randf_range(40.0, 90.0) * _scale
	var tw := fish.create_tween()
	tw.tween_property(fish, "position", to, fish.position.distance_to(to) / speed) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_interval(randf_range(0.3, 1.2))
	tw.tween_callback(_swim.bind(fish))


func _random_tank_spot(fish_size: Vector2) -> Vector2:
	return Vector2(randf_range(0, _tank.size.x - fish_size.x), randf_range(0, _tank.size.y - fish_size.y))


# ─── Section view (slots + details) ──────────────────────────────────

func _build_section_view(root: Control) -> void:
	var screen := get_viewport().get_visible_rect().size
	_section_view = PanelContainer.new()
	_section_view.add_theme_stylebox_override("panel", WoodPanel.make_dialog_panel_style())
	_section_view.size = Vector2(minf(1100, screen.x * 0.9), minf(660, screen.y * 0.85))
	_section_view.position = (screen - _section_view.size) / 2.0
	root.add_child(_section_view)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	_section_view.add_child(page)

	# header: Back · title · Aura · X
	var header := HBoxContainer.new()
	page.add_child(header)
	var back := _button("< Back")
	back.pressed.connect(_show_room)
	header.add_child(back)
	_title = _label("", WoodPanel.SIZE_PANEL_TITLE)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	_aura = _label("", WoodPanel.SIZE_STATUS)
	header.add_child(_aura)
	var x := _button("X")
	x.pressed.connect(close)
	header.add_child(x)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	page.add_child(body)

	# left: slots
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 1.6
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_grid)

	# right: details (parchment card)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", WoodPanel.make_parchment_style(18))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(card)
	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 8)
	card.add_child(details)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(120, 120)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	details.add_child(_icon)
	_name = _dark_label(WoodPanel.SIZE_CARD_NAME)
	details.add_child(_name)
	_info = _dark_label(WoodPanel.SIZE_SMALL)
	details.add_child(_info)
	_desc = _dark_label(WoodPanel.SIZE_SMALL)
	details.add_child(_desc)
	_price = _dark_label(WoodPanel.SIZE_STATUS)
	details.add_child(_price)
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_child(gap)
	_status = _dark_label(WoodPanel.SIZE_SMALL)
	details.add_child(_status)
	# Sell / Buy on the right, under everything
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	details.add_child(buttons)
	_sell = _button("Sell")
	_sell.pressed.connect(_trade.bind("sell"))
	buttons.add_child(_sell)
	_buy = _button("Buy")
	_buy.pressed.connect(_trade.bind("buy"))
	buttons.add_child(_buy)


func _open_section(key: String) -> void:
	_section = key
	_selected = ""
	_status.text = ""
	_room.visible = false
	_section_view.visible = true
	_render_section()
	WoodPanel.play_entrance(_section_view)


func _refresh() -> void:
	if _busy:
		return
	if _section != "":
		_render_section()
	else:
		_spawn_fish()


func _render_section() -> void:
	var title: String = SECTIONS[_section]["title"]
	if _section == "seeds":
		title += " · " + _current_season().capitalize()
	_title.text = title
	_aura.text = "Aura %d" % int(GameState.economy.get("aura_balance", 0))
	for child in _grid.get_children():
		child.queue_free()
	var rows := _rows_in(_section)
	if _selected == "" and not rows.is_empty():
		_selected = rows[0]["code"]
	for row in rows:
		_grid.add_child(_make_slot(row["code"], row["qty"]))
	if rows.is_empty():
		_selected = ""
		_grid.add_child(_label("Nothing stored here yet.", WoodPanel.SIZE_STATUS))
	_render_details()


# one square slot: icon + "×5"
func _make_slot(code: String, qty: int) -> Button:
	var slot := Button.new()
	slot.custom_minimum_size = Vector2(110, 110)
	slot.icon = _icon_for(code)
	slot.expand_icon = true
	slot.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	slot.text = "×%d" % qty
	slot.tooltip_text = _item(code)["name"]
	slot.add_theme_font_override("font", WoodPanel.PIXEL_FONT)
	slot.add_theme_font_size_override("font_size", WoodPanel.SIZE_SMALL)
	slot.add_theme_stylebox_override("normal", WoodPanel.make_wood_card_selected_style() if code == _selected else _slot_style())
	slot.add_theme_stylebox_override("hover", WoodPanel.make_wood_card_hover_style())
	slot.add_theme_stylebox_override("pressed", WoodPanel.make_wood_card_selected_style())
	slot.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if qty == 0:
		slot.modulate = Color(1, 1, 1, 0.6)   # in-season seed you don't own yet
	slot.pressed.connect(func() -> void:
		_selected = code
		_status.text = ""
		_render_section())
	return slot


func _slot_style() -> StyleBoxFlat:
	var sb := WoodPanel.make_wood_card_style()
	sb.set_content_margin_all(8)
	return sb


func _render_details() -> void:
	var has_item := _selected != ""
	_sell.disabled = true
	_buy.disabled = true
	if not has_item:
		_icon.texture = null
		_name.text = ""
		_info.text = ""
		_desc.text = ""
		_price.text = ""
		return
	var item := _item(_selected)
	var owned := _owned(_selected)
	_icon.texture = _icon_for(_selected)
	_name.text = item["name"]
	var info := "You have: %d" % owned
	if _section == "seeds":
		info += "   ·   Season: %s" % str(item["season"]).capitalize()
	_info.text = info
	_desc.text = item["description"]
	var lines := ["Sell price: %d Aura" % item["sell"] if item["sell"] > 0 else "Can't be sold"]
	if item["buy"] > 0 and _can_buy_now(item):
		lines.append("Buy price: %d Aura" % item["buy"])
	elif item["buy"] > 0:
		lines.append("Out of season - can't buy now")
	else:
		lines.append("Can't be bought here")
	_price.text = "\n".join(lines)
	_sell.disabled = _busy or owned <= 0 or item["sell"] <= 0
	_buy.disabled = _busy or item["buy"] <= 0 or not _can_buy_now(item)


func _can_buy_now(item: Dictionary) -> bool:
	if _section != "seeds":
		return true
	return item["season"] == "all" or item["season"] == _current_season()


# ─── Buy / Sell ──────────────────────────────────────────────────────

func _trade(action: String) -> void:
	if _busy or _selected == "":
		return
	var code := _selected
	var item := _item(code)
	if Global.is_logged_in():
		await _trade_online(action, code, item)
	else:
		_trade_offline(action, code, item)


# no server: change the local bag + Aura directly
func _trade_offline(action: String, code: String, item: Dictionary) -> void:
	if action == "buy":
		if not GameState.change_aura_offline(-int(item["buy"])):
			_status.text = "Not enough Aura."
			return
		var kind: Array = OFFLINE_KIND[_section]
		GameState.add_item_offline(code, item["name"], 1, kind[0], kind[1])
		_status.text = "Bought 1 %s (-%d Aura)" % [item["name"], item["buy"]]
	else:
		if not GameState.remove_item_offline(code, 1):
			return
		GameState.change_aura_offline(int(item["sell"]))
		_status.text = "Sold 1 %s (+%d Aura)" % [item["name"], item["sell"]]
	_render_section()


# logged in: ask the server, then reload the bag + Aura
func _trade_online(action: String, code: String, item: Dictionary) -> void:
	_busy = true
	_render_details()
	_status.text = "Please wait..."
	var body := {"item_code": code, "quantity": 1, "request_id": Crypto.new().generate_random_bytes(16).hex_encode()}
	if action == "sell":
		body["confirmed"] = true
	var response: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_POST, "/shop/" + action, body)
	if not is_instance_valid(self):
		return
	if response.get("ok", false):
		await GameState.refresh_gameplay()
		_status.text = ("Bought 1 %s" if action == "buy" else "Sold 1 %s") % item["name"]
	else:
		_status.text = APIClient.error_text(response)
	_busy = false
	_render_section()


# ─── Data helpers ────────────────────────────────────────────────────

# items for one section: [{code, qty}], sorted by name.
# Seeds also list every seed of the current season (qty 0 if you don't have it) so you can buy it.
func _rows_in(section: String) -> Array:
	var counts := {}
	for row in GameState.inventory:
		var code := str(row["item_code"])
		var category := str(row.get("item", {}).get("category", ""))
		if ItemCatalog.section_of(code, category) == section and int(row["quantity"]) > 0:
			counts[code] = int(counts.get(code, 0)) + int(row["quantity"])
	if section == "seeds":
		for code in ItemCatalog.seeds_for_season(_current_season()):
			if not counts.has(code):
				counts[code] = 0
	var rows := []
	for code in counts:
		rows.append({"code": code, "qty": counts[code]})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if (a["qty"] > 0) != (b["qty"] > 0):
			return a["qty"] > 0   # things you own first
		return str(_item(a["code"])["name"]) < str(_item(b["code"])["name"]))
	return rows


func _owned(code: String) -> int:
	var total := 0
	for row in GameState.inventory:
		if str(row["item_code"]) == code:
			total += int(row["quantity"])
	return total


# name / description / prices: the server's values when logged in, otherwise ItemCatalog
func _item(code: String) -> Dictionary:
	var info := ItemCatalog.info(code)
	if Global.is_logged_in():
		for row in GameState.inventory:
			if str(row["item_code"]) == code and row.get("item") is Dictionary:
				var item: Dictionary = row["item"]
				info["name"] = str(item.get("name", info["name"]))
				if str(item.get("description", "")) != "":
					info["description"] = str(item["description"])
				info["sell"] = int(item.get("sell_value", info["sell"]))
				info["buy"] = int(item["buy_value"]) if item.get("buy_value") != null else 0
				info["season"] = str(item.get("season", info["season"]))
				break
	return info


func _current_season() -> String:
	var season := str(GameState.world_state.get("current_season", ""))
	if season != "":
		return season
	var weather := get_tree().current_scene.find_child("WeatherManager", true, false)
	if weather and "current_season" in weather:
		return SEASONS[int(weather.current_season)]
	return "summer"


# ─── Small UI helpers ────────────────────────────────────────────────

# fish use their own pictures from Assets/fishes; everything else uses the game's item icons
func _icon_for(code: String) -> Texture2D:
	var path := "res://Assets/fishes/%s.png" % code
	if ResourceLoader.exists(path):
		return load(path)
	return WoodPanel.item_icon(code)


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", WoodPanel.PIXEL_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", WoodPanel.TEXT_COLOR)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	return label


# dark text for the parchment details card
func _dark_label(font_size: int) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", WoodPanel.PIXEL_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", WoodPanel.WOOD_DARK)
	return label


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(110, 48)
	b.add_theme_font_override("font", WoodPanel.PIXEL_FONT)
	b.add_theme_font_size_override("font_size", WoodPanel.SIZE_BUTTON)
	b.add_theme_color_override("font_color", WoodPanel.TEXT_COLOR)
	var normal := WoodPanel.make_wood_card_style()
	normal.set_content_margin_all(8)
	var hover := WoodPanel.make_wood_card_hover_style()
	hover.set_content_margin_all(8)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b
