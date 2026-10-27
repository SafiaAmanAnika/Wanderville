extends Button

class_name UISpriteSelector

const PIXEL_FONT := preload("res://Assets/fonts/BoldPixels.ttf")
const WOOD_SURFACE := Color(0.60, 0.43, 0.27)
const WOOD_BORDER := Color(0.38, 0.25, 0.13)
const WOOD_HOVER := Color(0.72, 0.56, 0.37)
const WOOD_BEVEL_LIGHT := Color(0.78, 0.62, 0.42)
const TEXT_COLOR := UiSkin.INK
const GOLDEN_BORDER := Color(1.0, 0.84, 0.0)

@onready var _portrait: TextureRect = %Portrait
@onready var _name_label: Label = %Name

var character_id: String = ""
var _style_normal: StyleBox
var _style_hover: StyleBox
var _style_selected: StyleBox
var _tween: Tween


func _ready() -> void:
	toggle_mode = true
	toggled.connect(_on_toggled)
	_build_styles()
	_apply_name_style()
	_update_visuals()

	await get_tree().process_frame
	pivot_offset = size / 2

	mouse_entered.connect(_on_hover)
	mouse_exited.connect(_on_unhover)


func _apply_name_style() -> void:
	if _name_label == null:
		return
	_name_label.add_theme_font_override("font", PIXEL_FONT)
	_name_label.add_theme_font_size_override("font_size", WoodPanel.SIZE_STATUS)   # "Female Farmer" fits the slot
	_name_label.add_theme_color_override("font_color", TEXT_COLOR)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _build_styles() -> void:
	# The pack's inventory slot frames each character portrait.
	_style_normal = UiSkin.slot()
	_style_hover = UiSkin.slot(UiSkin.HOVER_TINT)
	_style_selected = UiSkin.slot(UiSkin.GOLD_TINT)

	add_theme_stylebox_override("normal", _style_normal)
	add_theme_stylebox_override("hover", _style_hover)
	add_theme_stylebox_override("pressed", _style_selected)
	add_theme_stylebox_override("focus", _style_normal)


func set_character(id: String, character_name: String, portrait: Texture2D = null) -> void:
	character_id = id
	if _name_label != null:
		_name_label.text = character_name
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
		add_theme_stylebox_override("normal", _style_selected)
		add_theme_stylebox_override("hover", _style_selected)
		add_theme_stylebox_override("pressed", _style_selected)
		modulate = Color(1, 1, 1, 1)
	else:
		add_theme_stylebox_override("normal", _style_normal)
		add_theme_stylebox_override("hover", _style_hover)
		add_theme_stylebox_override("pressed", _style_normal)
		# The gold slot marks the choice; dimming the rest made them unreadable.
		modulate = Color.WHITE


func _on_hover() -> void:
	_kill_tween()
	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "scale", Vector2(1.03, 1.03), 0.15)


func _on_unhover() -> void:
	_kill_tween()
	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "scale", Vector2.ONE, 0.15)


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
