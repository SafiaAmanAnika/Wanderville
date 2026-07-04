extends Button

@onready var _thumbnail: TextureRect = %Thumbnail
@onready var _name_label: Label = %WorldName
@onready var _border: Panel = %Border

var world_id: String = ""


func _ready() -> void:
	var border_style := StyleBoxFlat.new()
	border_style.bg_color = Color.TRANSPARENT
	border_style.border_width_left = 3
	border_style.border_width_right = 3
	border_style.border_width_top = 3
	border_style.border_width_bottom = 3
	border_style.border_color = Color(1, 0.84, 0)
	border_style.corner_radius_top_left = 6
	border_style.corner_radius_top_right = 6
	border_style.corner_radius_bottom_right = 6
	border_style.corner_radius_bottom_left = 6
	_border.add_theme_stylebox_override("panel", border_style)

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.15, 0.15, 0.15)
	bg.corner_radius_top_left = 6
	bg.corner_radius_top_right = 6
	bg.corner_radius_bottom_right = 6
	bg.corner_radius_bottom_left = 6
	add_theme_stylebox_override("normal", bg)
	add_theme_stylebox_override("hover", bg)
	add_theme_stylebox_override("pressed", bg)

	_name_label.add_theme_font_size_override("font_size", 20)
	_name_label.add_theme_color_override("font_color", Color.WHITE)
	_name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_name_label.add_theme_constant_override("shadow_offset_x", 1)
	_name_label.add_theme_constant_override("shadow_offset_y", 1)


func set_world(id: String, world_name: String, thumbnail: Texture2D = null) -> void:
	world_id = id
	if _name_label != null:
		_name_label.text = world_name
	if _thumbnail != null and thumbnail != null:
		_thumbnail.texture = thumbnail


func set_selected(selected: bool) -> void:
	if _border != null:
		_border.visible = selected
