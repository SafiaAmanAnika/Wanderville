extends CanvasLayer
# Floor choice with live preview.
#   click a color   → previewed(floor)  (house shows it, free)
#   "Build … floor" → chosen(floor)     (pays the wood)
#   "Later"         → closed            (preview is removed)

signal chosen(floor_name: String)
signal previewed(floor_name: String)
signal closed

var _selected := ""
var _buttons := {}        # floor name → its button
var _build: Button


func _ready() -> void:
	layer = 30
	GameState.menu_open = true

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", WoodPanel.make_dialog_panel_style())
	UiSkin.ink_text(panel)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Choose your floor  ·  click a color to preview it"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", WoodPanel.PIXEL_FONT)
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	for f in HouseCatalog.FLOORS:
		var button := Button.new()
		button.text = f.capitalize()
		button.custom_minimum_size = Vector2(120, 70)
		button.add_theme_font_override("font", WoodPanel.PIXEL_FONT)
		button.pressed.connect(_select.bind(f))
		_buttons[f] = button
		row.add_child(button)
	_paint_buttons()

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 10)
	box.add_child(actions)
	var later := Button.new()
	later.text = "Later"
	later.pressed.connect(close)
	actions.add_child(later)
	_build = Button.new()
	_build.text = "Pick a color first"
	_build.disabled = true
	_build.pressed.connect(_on_build)
	actions.add_child(_build)

	# sit at the BOTTOM of the screen so the house above stays visible
	await get_tree().process_frame
	var screen := panel.get_viewport_rect().size
	panel.position = Vector2((screen.x - panel.size.x) / 2.0, screen.y - panel.size.y - 24)


func _select(floor_name: String) -> void:
	_selected = floor_name
	_paint_buttons()
	_build.disabled = false
	_build.text = "Build %s floor (%d wood)" % [floor_name.capitalize(), HouseCatalog.FLOOR_COST]
	previewed.emit(floor_name)     # house shows this floor right away


# each button is filled with its color; the selected one gets a thick gold border
func _paint_buttons() -> void:
	for f in _buttons:
		var style := StyleBoxFlat.new()
		style.bg_color = HouseCatalog.FLOOR_SWATCH[f]
		style.set_corner_radius_all(10)
		style.border_color = Color(1.0, 0.84, 0.0)
		style.set_border_width_all(6 if f == _selected else 0)
		var button: Button = _buttons[f]
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("hover", style)
		button.add_theme_stylebox_override("pressed", style)


func _on_build() -> void:
	chosen.emit(_selected)
	close()


func close() -> void:
	GameState.menu_open = false
	closed.emit()
	queue_free()
