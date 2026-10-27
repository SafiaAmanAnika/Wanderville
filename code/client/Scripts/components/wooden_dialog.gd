class_name WoodenDialog
extends Control

## Reusable wooden-themed dialog with open/close animations.

const PIXEL_FONT := preload("res://Assets/fonts/BoldPixels.ttf")

const WOOD_DARK := Color(0.28, 0.17, 0.08)
const WOOD_BORDER := Color(0.38, 0.25, 0.13)
const WOOD_FRAME := Color(0.45, 0.30, 0.17)
const WOOD_SURFACE := Color(0.55, 0.40, 0.25)
const TEXT_COLOR := UiSkin.INK

var _panel: PanelContainer
var _title_label: Label
var _content: VBoxContainer
var _button_bar: HBoxContainer
var _overlay: ColorRect
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build()


func _build() -> void:
	_ensure_tree()

	_overlay = ColorRect.new()
	_overlay.color = Color(0.05, 0.03, 0.01, 0.7)
	_overlay.anchors_preset = Control.PRESET_FULL_RECT
	_overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_overlay)

	_panel = PanelContainer.new()
	_panel.anchors_preset = Control.PRESET_CENTER
	_panel.pivot_offset = Vector2(280, 180)
	_panel.add_theme_stylebox_override("panel", _make_panel_style())
	UiSkin.ink_text(_panel)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.add_theme_font_override("font", PIXEL_FONT)
	_title_label.add_theme_font_size_override("font_size", WoodPanel.SIZE_PANEL_TITLE)
	_title_label.add_theme_color_override("font_color", TEXT_COLOR)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vbox.add_child(_title_label)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 8)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_content)

	_button_bar = HBoxContainer.new()
	_button_bar.add_theme_constant_override("separation", 12)
	_button_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(_button_bar)

	modulate = Color(1, 1, 1, 0)
	scale = Vector2(0.9, 0.9)

	await get_tree().process_frame
	_panel.pivot_offset = _panel.size / 2


func _make_panel_style() -> StyleBox:
	return UiSkin.panel()


func open(title: String) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	title_label.text = title
	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.set_parallel(true)
	_tween.tween_property(self, "scale", Vector2.ONE, 0.3)
	_tween.tween_property(self, "modulate:a", 1.0, 0.3)
	_tween.finished.connect(_on_open_finished)


func _on_open_finished() -> void:
	if _tween and _tween.is_valid():
		_tween.finished.disconnect(_on_open_finished)


func close() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.set_parallel(true)
	_tween.tween_property(self, "scale", Vector2(0.9, 0.9), 0.2)
	_tween.tween_property(self, "modulate:a", 0.0, 0.2)
	_tween.finished.connect(_on_close_finished)


func _on_close_finished() -> void:
	if _tween and _tween.is_valid():
		_tween.finished.disconnect(_on_close_finished)
	_tween = null
	queue_free()


func add_button(text: String) -> WoodButton:
	var btn := WoodButton.new()
	btn.text = text
	_button_bar.add_child(btn)
	return btn


func get_content() -> VBoxContainer:
	return _content


func _ensure_tree() -> void:
	if not is_node_ready():
		ready.connect(_build, Object.CONNECT_ONE_SHOT)


var title_label: Label:
	get:
		return _title_label
	set(_v):
		pass
