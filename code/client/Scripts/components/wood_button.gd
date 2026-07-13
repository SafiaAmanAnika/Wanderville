class_name WoodButton
extends Button

## Reusable wooden plank button with carved look, hover/press animations.

const PIXEL_FONT := preload("res://Assets/fonts/BoldPixels.ttf")

const WOOD_DARK := Color(0.28, 0.17, 0.08)
const WOOD_BORDER := Color(0.38, 0.25, 0.13)
const WOOD_BASE := Color(0.52, 0.36, 0.22)
const WOOD_SURFACE := Color(0.60, 0.43, 0.27)
const WOOD_HOVER := Color(0.72, 0.56, 0.37)
const WOOD_BEVEL_LIGHT := Color(0.78, 0.62, 0.42)
const TEXT_COLOR := Color(0.95, 0.91, 0.80)
const TEXT_HOVER_COLOR := Color(1.0, 0.97, 0.90)

@export var icon_type: String = ""

var _tween: Tween


func _ready() -> void:
	_build_styles()
	_apply_text_style()

	await get_tree().process_frame
	pivot_offset = size / 2

	mouse_entered.connect(_on_hover)
	mouse_exited.connect(_on_unhover)
	button_down.connect(_on_press)
	button_up.connect(_on_release)


func _apply_text_style() -> void:
	add_theme_font_override("font", PIXEL_FONT)
	add_theme_font_size_override("font_size", WoodPanel.SIZE_BUTTON)
	add_theme_color_override("font_color", TEXT_COLOR)
	add_theme_color_override("font_hover_color", TEXT_HOVER_COLOR)
	add_theme_color_override("font_pressed_color", TEXT_COLOR)
	add_theme_color_override("font_disabled_color", TEXT_COLOR * Color(1, 1, 1, 0.45))


func _build_styles() -> void:
	add_theme_stylebox_override("normal", _make_normal())
	add_theme_stylebox_override("hover", _make_hover())
	add_theme_stylebox_override("pressed", _make_pressed())
	add_theme_stylebox_override("disabled", _make_disabled())
	add_theme_stylebox_override("focus", _make_normal())


func _make_normal() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = WOOD_SURFACE
	sb.border_color = WOOD_BORDER
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	sb.shadow_color = Color(0.12, 0.06, 0.02, 0.55)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(2, 3)
	return sb


func _make_hover() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = WOOD_HOVER
	sb.border_color = WOOD_BEVEL_LIGHT
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	sb.shadow_color = Color(0.18, 0.10, 0.04, 0.6)
	sb.shadow_size = 5
	sb.shadow_offset = Vector2(2, 4)
	return sb


func _make_pressed() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = WOOD_BASE
	sb.border_color = WOOD_DARK
	sb.set_border_width_all(4)
	sb.border_width_top = 6
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 14
	sb.content_margin_bottom = 10
	sb.shadow_color = Color(0.10, 0.05, 0.01, 0.4)
	sb.shadow_size = 2
	sb.shadow_offset = Vector2(1, 1)
	return sb


func _make_disabled() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = WOOD_BASE * Color(0.65, 0.6, 0.55, 0.6)
	sb.border_color = WOOD_BORDER * Color(0.65, 0.6, 0.55, 0.6)
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	return sb


func _on_hover() -> void:
	_kill_tween()
	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "scale", Vector2(1.03, 1.03), 0.15)


func _on_unhover() -> void:
	_kill_tween()
	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "scale", Vector2.ONE, 0.15)


func _on_press() -> void:
	_kill_tween()
	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "scale", Vector2(0.97, 0.97), 0.05)


func _on_release() -> void:
	_kill_tween()
	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "scale", Vector2.ONE, 0.1)


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
