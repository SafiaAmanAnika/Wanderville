extends Control

const PIXEL_FONT := preload("res://Assets/fonts/BoldPixels.ttf")

@onready var _title: Label = %Title
@onready var _message: Label = %Message
@onready var _confirm_btn: Button = %ConfirmBtn
@onready var _cancel_btn: Button = %CancelBtn
@onready var _overlay: ColorRect = $Overlay
@onready var _panel: PanelContainer = $Center/Panel

var _tween: Tween


func _ready() -> void:
	visible = false
	WoodPanel.apply_panel_title_style(_title)
	_apply_label_font(_message, WoodPanel.SIZE_FIELD)
	_confirm_btn.pressed.connect(_on_confirm)
	_cancel_btn.pressed.connect(_on_cancel)


func _apply_label_font(label: Label, size: int) -> void:
	label.add_theme_font_override("font", PIXEL_FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", WoodPanel.TEXT_COLOR)


func show_dialog() -> void:
	visible = true
	modulate.a = 0.0
	_panel.scale = Vector2(0.9, 0.9)
	_panel.pivot_offset = _panel.size / 2.0

	_kill_tween()
	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "modulate:a", 1.0, 0.3)
	_tween.parallel().tween_property(_panel, "scale", Vector2.ONE, 0.35)


func _hide_dialog() -> void:
	_kill_tween()
	_tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "modulate:a", 0.0, 0.25)
	_tween.parallel().tween_property(_panel, "scale", Vector2(0.9, 0.9), 0.25)
	_tween.tween_callback(func() -> void: visible = false)


func _on_confirm() -> void:
	Global.clear_session()
	SceneManager.goto_title()


func _on_cancel() -> void:
	_hide_dialog()


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
