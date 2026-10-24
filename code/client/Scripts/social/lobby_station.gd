extends Node2D
## Small physical signboards that share the room's pixel and wood palette.
@export var title := "Board"
func _ready() -> void:
	var label := Label.new()
	label.text = title
	label.position = Vector2(-90, -62)
	label.size = Vector2(180, 44)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", preload("res://Assets/fonts/BoldPixels.ttf"))
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color("f5e7d3"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	z_index = 1
func _draw() -> void:
	draw_rect(Rect2(-65, -22, 12, 40), Color("583a28"))
	draw_rect(Rect2(53, -22, 12, 40), Color("583a28"))
	draw_rect(Rect2(-98, -68, 196, 54), Color("38291f"))
	draw_rect(Rect2(-94, -64, 188, 46), Color("85353e"))
	draw_rect(Rect2(-98, -68, 196, 54), Color("b88c5e"), false, 3)
