extends CanvasLayer
# Shop picker: the 12 storefront options in a 4 x 3 grid. Click one → picked(id).
# Thumbnails are cropped to each shop's visible_rect from placement.json, so the
# transparent padding around the artwork never shows in the buttons.

signal picked(id: String)
signal closed

const DATA := "res://Assets/marketplace/placement.json"
const ART := "res://Assets/marketplace/"
const WOOD_COST := 70


func _ready() -> void:
	layer = 30
	GameState.menu_open = true   # the player stops moving while the menu is open

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", WoodPanel.make_dialog_panel_style())
	UiSkin.ink_text(panel)
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)

	box.add_child(_label("Choose your shop  ·  %d wood  ·  You have %d"
			% [WOOD_COST, GameState.wood()], 26))

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	box.add_child(grid)

	for entry in _options():
		grid.add_child(_card(entry))

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.add_theme_font_override("font", WoodPanel.PIXEL_FONT)
	UiSkin.apply_button(close_button)
	close_button.pressed.connect(close)
	box.add_child(close_button)

	await get_tree().process_frame
	panel.position = (panel.get_viewport_rect().size - panel.size) / 2.0


# Every shop in placement.json except the general store, which nobody owns.
func _options() -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	if not (parsed is Dictionary):
		return []
	var out: Array = []
	for entry in parsed.get("shops", []):
		if str(entry["id"]) != "supershop":
			out.append(entry)
	return out


func _card(entry: Dictionary) -> VBoxContainer:
	var id := str(entry["id"])
	var card := VBoxContainer.new()
	card.add_child(_label(id.replace("shop_option_", "SHOP "), 20))

	var button := TextureButton.new()
	button.texture_normal = _thumbnail(entry)
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.custom_minimum_size = Vector2(200, 170)
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.tooltip_text = str(entry.get("architecture", ""))
	button.pressed.connect(_on_pick.bind(id))
	# The pack's shop card frames each choice.
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UiSkin.shop_card())
	frame.add_child(button)
	card.add_child(frame)
	return card


# Crop to the artwork itself; the source frames are 256x320 with a lot of empty space.
func _thumbnail(entry: Dictionary) -> Texture2D:
	var full: Texture2D = load(ART + str(entry["file"]))
	var r: Array = entry.get("visible_rect", [])
	if r.size() != 4:
		return full
	var atlas := AtlasTexture.new()
	atlas.atlas = full
	atlas.region = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	return atlas


func _on_pick(id: String) -> void:
	if GameState.wood() < WOOD_COST:
		HousePrompt.flash("You need %d wood to open a shop." % WOOD_COST)
		return
	picked.emit(id)
	close()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	GameState.menu_open = false
	closed.emit()
	queue_free()


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", WoodPanel.PIXEL_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", WoodPanel.TEXT_COLOR)
	return l
