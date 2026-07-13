class_name WoodPanel
extends PanelContainer

## Reusable wooden board panel for forms.
## Provides the carved-border, warm-brown panel look used across auth screens.

const WOOD_DARK := Color(0.28, 0.17, 0.08)
const WOOD_BORDER := Color(0.38, 0.25, 0.13)
const WOOD_FRAME := Color(0.45, 0.30, 0.17)
const WOOD_SURFACE := Color(0.55, 0.40, 0.25)

const PIXEL_FONT := preload("res://Assets/fonts/BoldPixels.ttf")
const TEXT_COLOR := Color(0.95, 0.91, 0.80)
const TEXT_SECONDARY := Color(0.80, 0.72, 0.58)
const TEXT_ERROR := Color(0.90, 0.38, 0.30)
const TEXT_PLACEHOLDER := Color(0.60, 0.50, 0.38)
const INPUT_BG := Color(0.22, 0.15, 0.08)
const INPUT_BORDER := Color(0.50, 0.36, 0.22)


func _ready() -> void:
	_apply_panel_style()
	_apply_theme_overrides()


func _apply_panel_style() -> void:
	# Outer frame – darker border to simulate carved edge
	var outer := StyleBoxFlat.new()
	outer.bg_color = WOOD_FRAME
	outer.border_color = WOOD_DARK
	outer.border_width_left = 6
	outer.border_width_right = 6
	outer.border_width_top = 6
	outer.border_width_bottom = 6
	outer.set_corner_radius_all(12)
	outer.shadow_color = Color(0.10, 0.05, 0.01, 0.65)
	outer.shadow_size = 8
	outer.shadow_offset = Vector2(3, 5)
	outer.content_margin_left = 28
	outer.content_margin_right = 28
	outer.content_margin_top = 24
	outer.content_margin_bottom = 24
	add_theme_stylebox_override("panel", outer)


func _apply_theme_overrides() -> void:
	# Label styling for title children
	add_theme_font_size_override("font_size", 16)


static func apply_title_style(label: Label) -> void:
	label.add_theme_font_override("font", PIXEL_FONT)
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


static func apply_field_style(edit: LineEdit) -> void:
	edit.add_theme_font_override("font", PIXEL_FONT)
	edit.add_theme_font_size_override("font_size", 14)
	edit.add_theme_color_override("font_color", TEXT_COLOR)
	edit.add_theme_color_override("font_placeholder_color", TEXT_PLACEHOLDER)

	var sb := StyleBoxFlat.new()
	sb.bg_color = INPUT_BG
	sb.border_color = INPUT_BORDER
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	edit.add_theme_stylebox_override("normal", sb)

	var focus_sb := StyleBoxFlat.new()
	focus_sb.bg_color = INPUT_BG
	focus_sb.border_color = Color(0.75, 0.60, 0.38)
	focus_sb.set_border_width_all(3)
	focus_sb.set_corner_radius_all(6)
	focus_sb.content_margin_left = 12
	focus_sb.content_margin_right = 12
	focus_sb.content_margin_top = 8
	focus_sb.content_margin_bottom = 8
	edit.add_theme_stylebox_override("focus", focus_sb)


static func apply_error_field_style(edit: LineEdit) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.35, 0.15, 0.12)
	sb.border_color = Color(0.85, 0.30, 0.25)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	edit.add_theme_stylebox_override("normal", sb)


static func clear_error_field_style(edit: LineEdit) -> void:
	edit.remove_theme_stylebox_override("normal")
	# Re-apply normal style
	var sb := StyleBoxFlat.new()
	sb.bg_color = INPUT_BG
	sb.border_color = INPUT_BORDER
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	edit.add_theme_stylebox_override("normal", sb)


static func apply_status_label(label: Label) -> void:
	label.add_theme_font_override("font", PIXEL_FONT)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", TEXT_SECONDARY)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


static func apply_error_label(label: Label) -> void:
	label.add_theme_font_override("font", PIXEL_FONT)
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", TEXT_ERROR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
