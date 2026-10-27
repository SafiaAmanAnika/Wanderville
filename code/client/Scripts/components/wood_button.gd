class_name WoodButton
extends Button

## Reusable wooden plank button (UiSkin art) with hover/press animations.

const PIXEL_FONT := preload("res://Assets/fonts/BoldPixels.ttf")

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


## The pack's plank button: parchment at rest, maroon under the pointer.
func _build_styles() -> void:
	UiSkin.apply_button(self)


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
