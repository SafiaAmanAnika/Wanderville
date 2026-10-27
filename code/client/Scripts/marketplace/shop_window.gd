extends CanvasLayer
## One player's shop. The shelf is whatever the owner stocked - nothing else.
## Yours also shows what sold. Friends' let you buy.
##
## Set shop_id / shop_name / is_mine before add_child().

signal closed

const CARD := Vector2(150, 158)
const MUTED := Color(0.56, 0.47, 0.37)   # faded ink on parchment

var shop_id := 0
var shop_name := ""
var is_mine := false

var _listings: Array = []
var _sales: Array = []
var _selected := ""
var _qty := 1
var _busy := false

var _title: Label
var _grid: GridContainer
var _status: Label

var _icon: TextureRect
var _name: Label
var _info: Label
var _desc: Label
var _qty_row: HBoxContainer
var _qty_label: Label
var _qty_less: Button
var _qty_more: Button
var _buy_button: Button


func _ready() -> void:
	layer = 20
	GameState.menu_open = true
	_build()
	await _reload()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	GameState.menu_open = false
	closed.emit()
	queue_free()


# ─── data ────────────────────────────────────────────────────────────

func _reload() -> void:
	var r: Dictionary = await APIClient.authenticated(
			HTTPClient.METHOD_GET, "/market/%d/listings" % shop_id)
	var data = APIClient.data_of(r)
	_listings = data if data is Array else []
	if is_mine:
		var s: Dictionary = await APIClient.authenticated(
				HTTPClient.METHOD_GET, "/market/%d/sales" % shop_id)
		var sd = APIClient.data_of(s)
		_sales = sd if sd is Array else []
	if is_instance_valid(self):
		_render()


func _buy(code: String, qty: int) -> void:
	if _busy or is_mine:
		return
	_busy = true
	_status.text = "Please wait..."
	var r: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_POST,
			"/market/buy", {"shop_id": shop_id, "item_code": code, "quantity": qty})
	_busy = false
	if not is_instance_valid(self):
		return
	if r.get("ok", false):
		await GameState.refresh_gameplay()
		_status.text = "Bought x%d" % qty
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
	UiSkin.ink_text(panel)
	panel.size = Vector2(minf(980, screen.x * 0.9), minf(620, screen.y * 0.85))
	panel.position = (screen - panel.size) / 2.0
	root.add_child(panel)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	panel.add_child(page)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	page.add_child(header)
	_title = _label("", WoodPanel.SIZE_PANEL_TITLE)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var x := _button("X")
	x.pressed.connect(close)
	header.add_child(x)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	page.add_child(body)

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

	_status = _label("", WoodPanel.SIZE_SMALL)
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

	_qty_row = HBoxContainer.new()
	_qty_row.add_theme_constant_override("separation", 8)
	details.add_child(_qty_row)
	var qty_word := _dark_label(WoodPanel.SIZE_SMALL)
	qty_word.text = "Amount"
	qty_word.autowrap_mode = TextServer.AUTOWRAP_OFF
	qty_word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	qty_word.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_qty_row.add_child(qty_word)
	_qty_less = _small_button("-")
	_qty_less.pressed.connect(func() -> void: _step_qty(-1))
	_qty_row.add_child(_qty_less)
	_qty_label = _dark_label(WoodPanel.SIZE_STATUS)
	_qty_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_qty_label.custom_minimum_size = Vector2(36, 0)
	_qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_qty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_qty_row.add_child(_qty_label)
	_qty_more = _small_button("+")
	_qty_more.pressed.connect(func() -> void: _step_qty(1))
	_qty_row.add_child(_qty_more)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	details.add_child(actions)
	_buy_button = _button("Buy")
	UiSkin.apply_buy_sell_button(_buy_button)
	_buy_button.custom_minimum_size.x = 150
	_buy_button.pressed.connect(func() -> void: _buy(_selected, _qty))
	actions.add_child(_buy_button)
	return card


# ─── rendering ───────────────────────────────────────────────────────

func _render() -> void:
	if not is_instance_valid(_grid):
		return
	var who := shop_name if shop_name != "" else "Shop"
	_title.text = ("%s  ·  your shelf" % who) if is_mine else who
	for child in _grid.get_children():
		child.queue_free()
	if _listings.is_empty():
		_grid.add_child(_label("Nothing for sale yet." if not is_mine
				else "Your shelf is empty.\nStock it at the General Store.", WoodPanel.SIZE_STATUS))
		_selected = ""
	else:
		for row in _listings:
			_grid.add_child(_listing_card(row))
	_render_details()


# one card: icon on top, the item's name under it, stock and price at the foot
func _listing_card(row: Dictionary) -> Button:
	var code := str(row["item_code"])
	var title := str(ItemCatalog.info(code)["name"])
	var slot := Button.new()
	slot.custom_minimum_size = CARD
	slot.tooltip_text = title
	var normal := UiSkin.slot(UiSkin.GOLD_TINT) if code == _selected else UiSkin.slot()
	normal.set_content_margin_all(8)
	slot.add_theme_stylebox_override("normal", normal)
	slot.add_theme_stylebox_override("hover", UiSkin.slot(UiSkin.HOVER_TINT))
	slot.add_theme_stylebox_override("pressed", UiSkin.slot(UiSkin.GOLD_TINT))
	slot.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	slot.pressed.connect(func() -> void:
		_selected = code
		_qty = 1
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
	box.add_child(icon)

	var name_label := _card_label(title, WoodPanel.SIZE_SMALL, WoodPanel.TEXT_COLOR)
	name_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(name_label)
	var stock := int(row["quantity"])
	box.add_child(_card_label("%d left  ·  %d Aura" % [stock, int(row["price"])],
			WoodPanel.SIZE_SMALL, WoodPanel.TEXT_COLOR if stock > 0 else MUTED))
	return slot


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


func _render_details() -> void:
	_qty_row.visible = not is_mine
	_buy_button.visible = not is_mine
	if _selected == "":
		_icon.texture = null
		_name.text = ""
		_info.text = _sales_text() if is_mine else "Pick something on the shelf."
		_desc.text = ""
		_qty_label.text = ""
		_buy_button.disabled = true
		_qty_less.disabled = true
		_qty_more.disabled = true
		return

	var row := _listing_row(_selected)
	var info := ItemCatalog.info(_selected)
	var stock := int(row.get("quantity", 0))
	var price := int(row.get("price", 0))
	var aura := int(GameState.economy.get("aura_balance", 0))
	_icon.texture = WoodPanel.item_icon(_selected)
	_name.text = str(info["name"])
	_desc.text = str(info["description"])
	_qty_label.text = str(_qty)

	if is_mine:
		_info.text = "On the shelf: %d at %d Aura\n%s" % [stock, price, _sales_text()]
		return

	var lines := ["%d Aura each  ·  total %d" % [price, price * _qty], "In stock: %d" % stock]
	if _qty > stock:
		lines.append("Not that many left")
	elif price * _qty > aura:
		lines.append("Not enough Aura")
	_info.text = "\n".join(lines)
	_buy_button.disabled = _busy or _qty > stock or price * _qty > aura
	_qty_less.disabled = _busy or _qty <= 1
	_qty_more.disabled = _busy or _qty >= maxi(1, stock)


func _sales_text() -> String:
	if _sales.is_empty():
		return "Nothing sold yet."
	var units := 0
	var earned := 0
	for sale in _sales:
		units += int(sale["quantity"])
		earned += int(sale["quantity"]) * int(sale["price"])
	return "Sold %d so far  ·  %d Aura earned" % [units, earned]


func _step_qty(delta: int) -> void:
	if _busy:
		return
	_qty = clampi(_qty + delta, 1, 99)
	_render_details()


func _listing_row(code: String) -> Dictionary:
	for row in _listings:
		if str(row["item_code"]) == code:
			return row
	return {}


# ─── small helpers ───────────────────────────────────────────────────

func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", WoodPanel.PIXEL_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", WoodPanel.TEXT_COLOR)
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
	UiSkin.apply_button(b)
	return b


func _small_button(text: String) -> Button:
	var b := _button(text)
	b.custom_minimum_size = Vector2(36, 36)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiSkin.apply_quantity_button(b, text == "+")
	return b
