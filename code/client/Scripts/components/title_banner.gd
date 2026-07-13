class_name TitleBanner
extends PanelContainer

## Hanging wooden sign banner for the game title.
## Draws rope/chain elements at the top for the "hanging" effect.

const PIXEL_FONT := preload("res://Assets/fonts/BoldPixels.ttf")

const WOOD_DARK := Color(0.28, 0.17, 0.08)
const WOOD_BORDER := Color(0.38, 0.25, 0.13)
const WOOD_FRAME := Color(0.42, 0.28, 0.15)
const WOOD_SURFACE := Color(0.58, 0.42, 0.26)
const WOOD_BEVEL_LIGHT := Color(0.72, 0.56, 0.38)
const WOOD_BEVEL_DARK := Color(0.30, 0.18, 0.09)
const ROPE_COLOR := Color(0.55, 0.45, 0.30)
const ROPE_SHADOW := Color(0.35, 0.25, 0.15)

const TITLE_COLOR := Color(0.98, 0.95, 0.85)
const SUBTITLE_COLOR := Color(0.82, 0.74, 0.58)

var title_label: Label
var subtitle_label: Label


func _ready() -> void:
	_apply_banner_style()
	_build_content()


func _apply_banner_style() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = WOOD_SURFACE
	sb.border_color = WOOD_BORDER
	sb.border_width_left = 5
	sb.border_width_right = 5
	sb.border_width_top = 6
	sb.border_width_bottom = 5
	sb.set_corner_radius_all(10)
	# Bevel effect: lighter top, darker bottom simulated via border widths
	sb.shadow_color = Color(0.10, 0.05, 0.01, 0.6)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(3, 5)
	sb.content_margin_left = 40
	sb.content_margin_right = 40
	sb.content_margin_top = 20
	sb.content_margin_bottom = 16
	add_theme_stylebox_override("panel", sb)


func _build_content() -> void:
	var vbox := VBoxContainer.new()
	vbox.name = "Content"
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	title_label = Label.new()
	title_label.name = "Title"
	title_label.text = "WanderVille"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_override("font", PIXEL_FONT)
	title_label.add_theme_font_size_override("font_size", WoodPanel.SIZE_BANNER_TITLE)
	title_label.add_theme_color_override("font_color", TITLE_COLOR)
	vbox.add_child(title_label)

	subtitle_label = Label.new()
	subtitle_label.name = "Subtitle"
	subtitle_label.text = "A Farming Adventure"
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.add_theme_font_override("font", PIXEL_FONT)
	subtitle_label.add_theme_font_size_override("font_size", WoodPanel.SIZE_BANNER_SUBTITLE)
	subtitle_label.add_theme_color_override("font_color", SUBTITLE_COLOR)
	vbox.add_child(subtitle_label)


func _draw() -> void:
	var w := size.x
	var h := size.y
	var rope_y_start := -18.0
	var anchor_left_x := w * 0.3
	var anchor_right_x := w * 0.7

	# Left rope
	_draw_rope_segment(Vector2(anchor_left_x, rope_y_start), Vector2(anchor_left_x + 2, 0))
	# Right rope
	_draw_rope_segment(Vector2(anchor_right_x, rope_y_start), Vector2(anchor_right_x - 2, 0))

	# Small nail / hook dots at the top of each rope
	draw_circle(Vector2(anchor_left_x, rope_y_start), 2.5, ROPE_SHADOW)
	draw_circle(Vector2(anchor_left_x, rope_y_start), 1.5, ROPE_COLOR)
	draw_circle(Vector2(anchor_right_x, rope_y_start), 2.5, ROPE_SHADOW)
	draw_circle(Vector2(anchor_right_x, rope_y_start), 1.5, ROPE_COLOR)


func _draw_rope_segment(from: Vector2, to: Vector2) -> void:
	# Shadow
	draw_line(from, to, ROPE_SHADOW, 3.0)
	# Main rope
	draw_line(from, to, ROPE_COLOR, 2.0)
