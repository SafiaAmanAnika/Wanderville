extends CanvasLayer
# Bottom-of-screen message box. Use from anywhere:
#   HousePrompt.show_text("Press H to open the door")   → stays until hide_text()
#   HousePrompt.flash("Get 10 wood to build the floor")  → disappears by itself

var _panel: PanelContainer
var _label: Label
var _flash_id := 0


func _ready() -> void:
	layer = 40
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.28, 0.17, 0.08, 0.92)
	style.border_color = Color(1.0, 0.84, 0.0)
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", style)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_override("font", WoodPanel.PIXEL_FONT)
	_label.add_theme_font_size_override("font_size", 24)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_panel.add_child(_label)
	add_child(_panel)
	_panel.visible = false


func show_text(text: String) -> void:
	_flash_id += 1   # cancels a running flash
	_label.text = text
	_panel.visible = true
	await get_tree().process_frame   # let it measure the new text
	var screen := _panel.get_viewport_rect().size
	_panel.position = Vector2((screen.x - _panel.size.x) / 2.0, screen.y - _panel.size.y - 30)


func hide_text() -> void:
	_panel.visible = false


func flash(text: String, seconds := 2.5) -> void:
	show_text(text)
	_flash_id += 1
	var my_id := _flash_id
	await get_tree().create_timer(seconds).timeout
	if my_id == _flash_id:   # nothing newer replaced it
		hide_text()
