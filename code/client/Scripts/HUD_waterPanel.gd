extends Panel

@onready var label: Label = $WaterAmount

func _ready() -> void:
	var box_size := Vector2(140, 50)
	custom_minimum_size = box_size
	size = box_size
	position = Vector2(20, 20)  # top-left margin

	add_theme_stylebox_override("panel", UiSkin.card())

	label.size = box_size
	label.position = Vector2.ZERO
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", WoodPanel.SIZE_STATUS)
	label.add_theme_color_override("font_color", UiSkin.INK)

	GameState.water_changed.connect(_on_water_changed)
	_on_water_changed(GameState.water_drops)

func _on_water_changed(new_amount: int) -> void:
	label.text = "💧 %d / %d" % [new_amount, GameState.MAX_WATER]
