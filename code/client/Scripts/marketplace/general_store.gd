extends CanvasLayer
## General Store (the supershop in the middle of the marketplace).
##
##  BUY   - the server's catalog (GET /shop). Items above your level are greyed
##          with "Lv N"; rare stock rotates daily (in_stock).
##  STOCK - move items out of your bag onto your own shop's shelf
##          (POST /market/listings) and take them back (.../listings/remove).
##
## Esc closes. No selling for Aura here: that is what your own shop is for.

signal closed

const BUY := "buy"
const STOCK := "stock"
const PRICE_STEP := 5
const CARD := Vector2(150, 158)
const GOLD := Color(1.0, 0.84, 0.0)
const MUTED := Color(0.78, 0.71, 0.60)

# The same rooms the storage house uses, in the same order, so the two screens
# describe your bag the same way. ItemCatalog.section_of() decides which an item
# belongs to.
const SECTIONS := [
	["crops", "Crops"],
	["seeds", "Seeds"],
	["fish", "Fish"],
	["misc", "Materials"],
]

var shop_id := 0            ## your own shop's id; 0 = you have not opened one yet
## True when the marketplace could not reach the server, so shop_id 0 proves nothing.
var shop_unknown := false
## What the server said when it failed, so the screen names the cause.
var shop_error := ""

var _tab := BUY
var _catalog: Array = []    ## rows from GET /shop
var _shelf: Array = []      ## rows from GET /market/<shop_id>/listings
var _selected := ""
## Which bag section the Stock tab is showing; "" = the list of sections.
var _stock_section := ""
var _qty := 1
var _price := 10
var _busy := false

# chrome
var _title: Label
var _grid: GridContainer
var _status: Label
var _buy_tab: Button
var _stock_tab: Button

# details card
var _icon: TextureRect
var _name: Label
var _info: Label
var _desc: Label
var _qty_label: Label
var _qty_less: Button
var _qty_more: Button
var _price_row: HBoxContainer
var _price_label: Label
var _action: Button
var _take: Button


func _ready() -> void:
	layer = 20
	GameState.menu_open = true
	_build()
	GameState.inventory_updated.connect(func(_items: Array) -> void: _render())
	GameState.economy_updated.connect(func(_data: Dictionary) -> void: _render())
	await _reload()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		# Esc steps back out of a section first, like the storage house.
		if _tab == STOCK and _stock_section != "":
			_open_section("")
			return
		close()


func close() -> void:
	GameState.menu_open = false
	closed.emit()
	queue_free()


# ─── data ────────────────────────────────────────────────────────────

func _reload() -> void:
	if _tab == BUY:
		var r: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_GET, "/shop")
		var data = APIClient.data_of(r)
		_catalog = data.get("items", []) if data is Dictionary else []
	elif shop_id > 0:
		var r: Dictionary = await APIClient.authenticated(
				HTTPClient.METHOD_GET, "/market/%d/listings" % shop_id)
		var data = APIClient.data_of(r)
		_shelf = data if data is Array else []
	if is_instance_valid(self):
		_render()


func _buy(code: String, qty: int) -> void:
	if _busy:
		return
	_busy = true
	_status.text = "Please wait..."
	var body := {"item_code": code, "quantity": qty,
			"request_id": Crypto.new().generate_random_bytes(16).hex_encode()}
	var r: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_POST, "/shop/buy", body)
	_busy = false
	if not is_instance_valid(self):
		return
	if r.get("ok", false):
		await GameState.refresh_gameplay()
		_status.text = "Bought x%d" % qty
	else:
		_status.text = APIClient.error_text(r)
	await _reload()


func _put_on_shelf(code: String, qty: int, price: int) -> void:
	if _busy or shop_id <= 0:
		return
	_busy = true
	_status.text = "Please wait..."
	var r: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_POST,
			"/market/listings", {"item_code": code, "quantity": qty, "price": price})
	_busy = false
	if not is_instance_valid(self):
		return
	if r.get("ok", false):
		await GameState.refresh_gameplay()
		_status.text = "Shelved x%d at %d Aura" % [qty, price]
	else:
		_status.text = APIClient.error_text(r)
	await _reload()


func _take_back(code: String, qty: int) -> void:
	if _busy or shop_id <= 0:
		return
	_busy = true
	_status.text = "Please wait..."
	var r: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_POST,
			"/market/listings/remove", {"item_code": code, "quantity": qty})
	_busy = false
	if not is_instance_valid(self):
		return
	if r.get("ok", false):
		await GameState.refresh_gameplay()
		_status.text = "Took x%d back" % qty
	else:
		_status.text = APIClient.error_text(r)
	await _reload()


# ─── layout ──────────────────────────────────────────────────────────

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = WoodPanel.make_overlay_color()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var screen := get_viewport().get_visible_rect().size
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", WoodPanel.make_dialog_panel_style())
	panel.size = Vector2(minf(1060, screen.x * 0.9), minf(680, screen.y * 0.88))
	panel.position = (screen - panel.size) / 2.0
	root.add_child(panel)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	panel.add_child(page)

	# header: tabs · title · X
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	page.add_child(header)
	_buy_tab = _button("Buy")
	_buy_tab.custom_minimum_size.x = 130
	_buy_tab.pressed.connect(func() -> void: _switch(BUY))
	header.add_child(_buy_tab)
	_stock_tab = _button("Stock my shop")
	_stock_tab.custom_minimum_size.x = 210
	_stock_tab.pressed.connect(func() -> void: _switch(STOCK))
	header.add_child(_stock_tab)
	_title = _label("", WoodPanel.SIZE_STATUS)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var x := _button("X")
	x.pressed.connect(close)
	header.add_child(x)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	page.add_child(body)

	# left: the grid of things
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 1.6
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_grid)

	body.add_child(_build_details())

	_status = _label("", WoodPanel.SIZE_STATUS)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	page.add_child(_status)


func _build_details() -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", WoodPanel.make_parchment_style(18))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 8)
	card.add_child(details)

	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(110, 110)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	details.add_child(_icon)
	_name = _dark_label(WoodPanel.SIZE_CARD_NAME)
	details.add_child(_name)
	_info = _dark_label(WoodPanel.SIZE_SMALL)
	details.add_child(_info)
	_desc = _dark_label(WoodPanel.SIZE_SMALL)
	details.add_child(_desc)

	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_child(gap)

	# Amount  -  N  +
	var qty_row := HBoxContainer.new()
	qty_row.add_theme_constant_override("separation", 8)
	details.add_child(qty_row)
	var qty_word := _dark_label(WoodPanel.SIZE_SMALL)
	qty_word.text = "Amount"
	qty_word.autowrap_mode = TextServer.AUTOWRAP_OFF
	qty_word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	qty_word.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qty_row.add_child(qty_word)
	_qty_less = _small_button("-")
	_qty_less.pressed.connect(func() -> void: _step_qty(-1))
	qty_row.add_child(_qty_less)
	_qty_label = _dark_label(WoodPanel.SIZE_STATUS)
	_qty_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_qty_label.custom_minimum_size = Vector2(36, 0)
	_qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_qty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	qty_row.add_child(_qty_label)
	_qty_more = _small_button("+")
	_qty_more.pressed.connect(func() -> void: _step_qty(1))
	qty_row.add_child(_qty_more)

	# Price  -  N  +     (stock tab only)
	_price_row = HBoxContainer.new()
	_price_row.add_theme_constant_override("separation", 8)
	details.add_child(_price_row)
	var price_word := _dark_label(WoodPanel.SIZE_SMALL)
	price_word.text = "Price each"
	price_word.autowrap_mode = TextServer.AUTOWRAP_OFF
	price_word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	price_word.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_price_row.add_child(price_word)
	var price_less := _small_button("-")
	price_less.pressed.connect(func() -> void: _step_price(-PRICE_STEP))
	_price_row.add_child(price_less)
	_price_label = _dark_label(WoodPanel.SIZE_STATUS)
	_price_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_price_label.custom_minimum_size = Vector2(46, 0)
	_price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_price_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_price_row.add_child(_price_label)
	var price_more := _small_button("+")
	price_more.pressed.connect(func() -> void: _step_price(PRICE_STEP))
	_price_row.add_child(price_more)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 10)
	details.add_child(actions)
	_take = _button("Take back")
	_take.custom_minimum_size.x = 150
	_take.pressed.connect(func() -> void: _take_back(_selected, _qty))
	actions.add_child(_take)
	_action = _button("Buy")
	_action.custom_minimum_size.x = 170
	_action.pressed.connect(_do_action)
	actions.add_child(_action)
	return card


# ─── rendering ───────────────────────────────────────────────────────

func _switch(tab: String) -> void:
	if _busy or _tab == tab:
		return
	_tab = tab
	_selected = ""
	_stock_section = ""
	_qty = 1
	_status.text = ""
	await _reload()


func _render() -> void:
	if not is_instance_valid(_grid):
		return
	_style_tab(_buy_tab, _tab == BUY)
	_style_tab(_stock_tab, _tab == STOCK)
	for child in _grid.get_children():
		child.queue_free()

	if _tab == BUY:
		_title.text = "General Store  ·  Aura %d  ·  Level %d" % [
				int(GameState.economy.get("aura_balance", 0)),
				int(GameState.experience.get("level", 1))]
		for row in _sorted_catalog():
			_grid.add_child(_catalog_card(row))
		if _catalog.is_empty():
			_grid.add_child(_label("Nothing in the catalog right now.", WoodPanel.SIZE_STATUS))
	else:
		_title.text = "Stock your shop"
		if shop_id <= 0 and shop_unknown:
			_grid.add_child(_label("Couldn't load your shop.\n%s\nLeave the marketplace and come back to try again." % shop_error,
					WoodPanel.SIZE_STATUS))
		elif shop_id <= 0:
			_grid.add_child(_label("The server says this account owns no shop.\nIf you opened one, you may be signed in as a different account.",
					WoodPanel.SIZE_STATUS))
		elif _stock_section == "":
			for entry in SECTIONS:
				_grid.add_child(_section_card(str(entry[0]), str(entry[1])))
		else:
			_title.text = "Stock your shop  ·  %s" % _section_title(_stock_section)
			_grid.add_child(_back_card())
			var any := false
			for row in _rows_in(_stock_section):
				_grid.add_child(_bag_card(row))
				any = true
			if not any:
				_grid.add_child(_label("Nothing here yet.", WoodPanel.SIZE_STATUS))
	_render_details()


# buyable first, then by unlock level, then alphabetically
func _sorted_catalog() -> Array:
	var rows := _catalog.duplicate()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_ok := not bool(a.get("locked", false)) and bool(a.get("in_stock", true))
		var b_ok := not bool(b.get("locked", false)) and bool(b.get("in_stock", true))
		if a_ok != b_ok:
			return a_ok
		var a_lv := int(a.get("required_level", 1))
		var b_lv := int(b.get("required_level", 1))
		if a_lv != b_lv:
			return a_lv < b_lv
		return str(a.get("name", "")) < str(b.get("name", "")))
	return rows


func _catalog_card(row: Dictionary) -> Button:
	var code := str(row["item_code"])
	var title := str(row.get("name", ItemCatalog.info(code)["name"]))
	var locked := bool(row.get("locked", false))
	var stocked := bool(row.get("in_stock", true))
	if locked:
		return _slot(code, title, "Unlocks at Lv %d" % int(row.get("required_level", 1)), GOLD, true)
	if not stocked:
		return _slot(code, title, "Not stocked today", MUTED, true)
	return _slot(code, title, "%d Aura" % int(row.get("buy_value", 0)), WoodPanel.TEXT_COLOR, false)


## Every bag row that belongs to one section, in the order the server sent them.
func _rows_in(section: String) -> Array:
	var out := []
	for row in GameState.inventory:
		if int(row.get("quantity", 0)) <= 0:
			continue
		var code := str(row.get("item_code", ""))
		var category := str(row.get("item", {}).get("category", ""))
		if ItemCatalog.section_of(code, category) == section:
			out.append(row)
	return out


func _section_title(section: String) -> String:
	for entry in SECTIONS:
		if str(entry[0]) == section:
			return str(entry[1])
	return section.capitalize()


## One room of the bag. The icon is whatever you own most of in it, so an empty
## section reads as empty at a glance.
func _section_card(section: String, title: String) -> Button:
	var rows := _rows_in(section)
	var total := 0
	var best := ""
	var best_count := -1
	for row in rows:
		var quantity := int(row["quantity"])
		total += quantity
		if quantity > best_count:
			best_count = quantity
			best = str(row["item_code"])
	var subtitle := "%d item kinds  ·  %d total" % [rows.size(), total] if total > 0 else "empty"
	var card := _plain_card(title, subtitle, WoodPanel.TEXT_SECONDARY if total > 0 else MUTED,
			WoodPanel.item_icon(best) if best != "" else null, total == 0)
	card.pressed.connect(func() -> void: _open_section(section))
	return card


func _back_card() -> Button:
	var card := _plain_card("Back", "all sections", WoodPanel.TEXT_SECONDARY, null, false)
	card.pressed.connect(func() -> void: _open_section(""))
	return card


func _open_section(section: String) -> void:
	_stock_section = section
	_selected = ""
	_status.text = ""
	_render()


## A card that is not an item: no selection, no price, just a label and an icon.
func _plain_card(title: String, subtitle: String, subtitle_color: Color,
		icon_texture: Texture2D, dim: bool) -> Button:
	var slot := Button.new()
	slot.custom_minimum_size = CARD
	slot.tooltip_text = title
	var normal := WoodPanel.make_wood_card_style()
	normal.set_content_margin_all(8)
	slot.add_theme_stylebox_override("normal", normal)
	slot.add_theme_stylebox_override("hover", WoodPanel.make_wood_card_hover_style())
	slot.add_theme_stylebox_override("pressed", WoodPanel.make_wood_card_selected_style())
	slot.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	slot.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)

	var icon := TextureRect.new()
	icon.texture = icon_texture
	icon.custom_minimum_size = Vector2(0, 58)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.modulate = Color(1, 1, 1, 0.4) if dim else Color.WHITE
	box.add_child(icon)

	var name_label := _card_label(title, WoodPanel.SIZE_CARD_NAME, WoodPanel.TEXT_COLOR if not dim else MUTED)
	name_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(name_label)
	box.add_child(_card_label(subtitle, WoodPanel.SIZE_SMALL, subtitle_color))
	return slot


func _bag_card(row: Dictionary) -> Button:
	var code := str(row["item_code"])
	var title := str(row.get("item", {}).get("name", ItemCatalog.info(code)["name"]))
	return _slot(code, title, "you have %d" % int(row["quantity"]), WoodPanel.TEXT_COLOR, false)


# one card: icon on top, the item's name under it, one line of status at the foot
func _slot(code: String, title: String, subtitle: String, subtitle_color: Color, dim: bool) -> Button:
	var slot := Button.new()
	slot.custom_minimum_size = CARD
	slot.tooltip_text = title
	var normal := WoodPanel.make_wood_card_selected_style() if code == _selected else WoodPanel.make_wood_card_style()
	normal.set_content_margin_all(8)
	slot.add_theme_stylebox_override("normal", normal)
	slot.add_theme_stylebox_override("hover", WoodPanel.make_wood_card_hover_style())
	slot.add_theme_stylebox_override("pressed", WoodPanel.make_wood_card_selected_style())
	slot.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	slot.pressed.connect(func() -> void:
		_selected = code
		_qty = 1
		_price = maxi(1, int(ItemCatalog.info(code)["sell"]) * 2)
		_status.text = ""
		_render())

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	slot.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)

	var icon := TextureRect.new()
	icon.texture = WoodPanel.item_icon(code)
	icon.custom_minimum_size = Vector2(0, 58)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.modulate = Color(1, 1, 1, 0.4) if dim else Color.WHITE
	box.add_child(icon)

	var name_label := _card_label(title, WoodPanel.SIZE_SMALL, WoodPanel.TEXT_COLOR if not dim else MUTED)
	name_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(name_label)
	box.add_child(_card_label(subtitle, WoodPanel.SIZE_SMALL, subtitle_color))
	return slot


func _render_details() -> void:
	_price_row.visible = _tab == STOCK
	if _selected == "":
		_icon.texture = null
		_name.text = ""
		if _tab == STOCK and _stock_section == "":
			_info.text = "Pick a section on the left."
		else:
			_info.text = "Pick something on the left."
		_desc.text = ""
		_qty_label.text = ""
		_price_label.text = ""
		# Name the action even while it is greyed out, or the Stock tab keeps
		# showing "Buy" left over from the other tab.
		_action.text = "Buy" if _tab == BUY else "Put on shelf"
		_action.disabled = true
		_take.visible = false
		_qty_less.disabled = true
		_qty_more.disabled = true
		return

	var info := ItemCatalog.info(_selected)
	_icon.texture = WoodPanel.item_icon(_selected)
	_name.text = str(info["name"])
	_desc.text = str(info["description"])
	_qty_label.text = str(_qty)
	_price_label.text = str(_price)
	_qty_less.disabled = _busy or _qty <= 1
	_qty_more.disabled = _busy or _qty >= 99

	if _tab == BUY:
		var row := _catalog_row(_selected)
		var each := int(row.get("buy_value", 0))
		var aura := int(GameState.economy.get("aura_balance", 0))
		var locked := bool(row.get("locked", false))
		var stocked := bool(row.get("in_stock", true))
		var lines := ["%d Aura each  ·  total %d" % [each, each * _qty]]
		if locked:
			lines.append("Unlocks at level %d" % int(row.get("required_level", 1)))
		elif not stocked:
			lines.append("Not stocked today")
		elif each * _qty > aura:
			lines.append("Not enough Aura")
		_info.text = "\n".join(lines)
		_action.text = "Buy"
		_action.disabled = _busy or locked or not stocked or each * _qty > aura
		_take.visible = false
	else:
		var owned := _owned(_selected)
		var shelf := _shelf_row(_selected)
		var on_shelf := int(shelf.get("quantity", 0))
		var lines := ["In your bag: %d" % owned]
		if on_shelf > 0:
			lines.append("On the shelf: %d at %d Aura" % [on_shelf, int(shelf.get("price", 0))])
		_info.text = "\n".join(lines)
		_action.text = "Put on shelf"
		_action.disabled = _busy or owned < _qty or _price <= 0
		_take.visible = on_shelf > 0
		_take.disabled = _busy or on_shelf < _qty


func _do_action() -> void:
	if _selected == "":
		return
	if _tab == BUY:
		_buy(_selected, _qty)
	else:
		_put_on_shelf(_selected, _qty, _price)


func _step_qty(delta: int) -> void:
	if _busy:
		return
	_qty = clampi(_qty + delta, 1, 99)
	_render_details()


func _step_price(delta: int) -> void:
	if _busy:
		return
	_price = clampi(_price + delta, 1, 9999)
	_render_details()


# ─── small helpers ───────────────────────────────────────────────────

func _catalog_row(code: String) -> Dictionary:
	for row in _catalog:
		if str(row["item_code"]) == code:
			return row
	return {}


func _shelf_row(code: String) -> Dictionary:
	for row in _shelf:
		if str(row["item_code"]) == code:
			return row
	return {}


func _owned(code: String) -> int:
	var total := 0
	for row in GameState.inventory:
		if str(row["item_code"]) == code:
			total += int(row["quantity"])
	return total


# the open tab is the lit one; the other stays clickable
func _style_tab(button: Button, active: bool) -> void:
	var style := WoodPanel.make_wood_card_selected_style() if active else WoodPanel.make_wood_card_style()
	style.set_content_margin_all(8)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_color_override("font_color", WoodPanel.TEXT_COLOR if active else MUTED)


func _card_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", WoodPanel.PIXEL_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


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


func _small_button(text: String) -> Button:
	var b := _button(text)
	b.custom_minimum_size = Vector2(36, 36)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b
