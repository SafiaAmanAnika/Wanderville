extends CanvasLayer
# House menu: 6 houses in a 3 x 2 grid. Click one → picked(id).

signal picked(id: int)
signal closed


func _ready() -> void:
	layer = 30
	GameState.menu_open = true   # the player stops moving while the menu is open

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", WoodPanel.make_dialog_panel_style())
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)

	var title := _label("Choose your house  ·  Outer layer: %d wood  ·  You have %d" % [HouseCatalog.OUTER_COST, GameState.wood()], 26)
	box.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	box.add_child(grid)

	for id in range(1, 7):
		var card := VBoxContainer.new()
		card.add_child(_label("HOUSE %d" % id, 24))
		var button := TextureButton.new()
		button.texture_normal = HouseCatalog.exterior_texture(id)
		button.ignore_texture_size = true
		button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		button.custom_minimum_size = Vector2(288, 192)       # 192x128 picture x1.5
		button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.pressed.connect(_on_pick.bind(id))
		card.add_child(button)
		grid.add_child(card)

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close)
	box.add_child(close_button)

	await get_tree().process_frame
	panel.position = (panel.get_viewport_rect().size - panel.size) / 2.0


func _on_pick(id: int) -> void:
	if GameState.wood() < HouseCatalog.OUTER_COST:
		HousePrompt.flash("You need %d wood to build the outer layer." % HouseCatalog.OUTER_COST)
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
