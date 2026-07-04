extends Button

class_name UISpriteSelector

@onready var _portrait: TextureRect = %Portrait
@onready var _name_label: Label = %Name

var character_id: String = ""
var _style_normal: StyleBoxFlat
var _style_selected: StyleBoxFlat


func _ready() -> void:
	toggle_mode = true
	toggled.connect(_on_toggled)
	_build_styles()
	_update_visuals()


func _build_styles() -> void:
	_style_normal = StyleBoxFlat.new()
	_style_normal.bg_color = Color(0.2, 0.2, 0.2, 1)
	_style_normal.border_width_left = 2
	_style_normal.border_width_right = 2
	_style_normal.border_width_top = 2
	_style_normal.border_width_bottom = 2
	_style_normal.border_color = Color(0.5, 0.5, 0.5, 1)
	_style_normal.corner_radius_top_left = 8
	_style_normal.corner_radius_top_right = 8
	_style_normal.corner_radius_bottom_right = 8
	_style_normal.corner_radius_bottom_left = 8

	_style_selected = StyleBoxFlat.new()
	_style_selected.bg_color = Color(0.2, 0.2, 0.2, 1)
	_style_selected.border_width_left = 3
	_style_selected.border_width_right = 3
	_style_selected.border_width_top = 3
	_style_selected.border_width_bottom = 3
	_style_selected.border_color = Color(1, 0.84, 0, 1)
	_style_selected.corner_radius_top_left = 8
	_style_selected.corner_radius_top_right = 8
	_style_selected.corner_radius_bottom_right = 8
	_style_selected.corner_radius_bottom_left = 8


func set_character(id: String, name: String, portrait: Texture2D = null) -> void:
	character_id = id
	if _name_label != null:
		_name_label.text = name
	if _portrait != null and portrait != null:
		_portrait.texture = portrait


func get_character_id() -> String:
	return character_id


func _on_toggled(_toggled_on: bool) -> void:
	_update_visuals()


func _update_visuals() -> void:
	if not is_inside_tree():
		return
	if button_pressed:
		if _style_selected:
			add_theme_stylebox_override("normal", _style_selected)
			add_theme_stylebox_override("hover", _style_selected)
			add_theme_stylebox_override("pressed", _style_selected)
		modulate = Color(1, 1, 1, 1)
	else:
		if _style_normal:
			add_theme_stylebox_override("normal", _style_normal)
			add_theme_stylebox_override("hover", _style_normal)
			add_theme_stylebox_override("pressed", _style_normal)
		modulate = Color(0.5, 0.5, 0.5, 0.7)
