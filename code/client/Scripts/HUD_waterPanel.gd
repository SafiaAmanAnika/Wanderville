extends Panel

@onready var label: Label = $WaterAmount

func _ready() -> void:
	var box_size := Vector2(140, 50)
	custom_minimum_size = box_size
	size = box_size
	position = Vector2(20, 20)  # top-left margin

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.4, 0.75, 0.85)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(1, 1, 1, 0.6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	add_theme_stylebox_override("panel", style)

	label.size = box_size
	label.position = Vector2.ZERO
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", WoodPanel.SIZE_STATUS)
	label.add_theme_color_override("font_color", Color.WHITE)

	GameState.water_changed.connect(_on_water_changed)
	_on_water_changed(GameState.water_drops)

func _on_water_changed(new_amount: int) -> void:
	label.text = "💧 %d / %d" % [new_amount, GameState.MAX_WATER]
