extends Button

const PIXEL_FONT := preload("res://Assets/fonts/BoldPixels.ttf")

const WOOD_SURFACE := Color(0.60, 0.43, 0.27)
const WOOD_BORDER := Color(0.38, 0.25, 0.13)
const WOOD_HOVER := Color(0.72, 0.56, 0.37)
const WOOD_BEVEL_LIGHT := Color(0.78, 0.62, 0.42)
const WOOD_DARK := Color(0.28, 0.17, 0.08)
const TEXT_COLOR := Color(0.95, 0.91, 0.80)
const TEXT_SECONDARY := Color(0.82, 0.74, 0.58)
const PARCHMENT_BG := Color(0.85, 0.78, 0.60)
const PARCHMENT_DARK := Color(0.80, 0.72, 0.55)

const GOLDEN := Color(1.0, 0.84, 0.0)
const HOVER_SCALE := 1.03

@onready var _thumbnail: TextureRect = %Thumbnail
@onready var _name_label: Label = %WorldName
@onready var _border: Panel = %Border
@onready var _overlay: ColorRect = $Overlay

var world_id: String = ""

var _info_label: Label
var _is_selected: bool = false
var _is_hovered: bool = false
var _original_scale: Vector2

func _ready() -> void:
	_original_scale = scale

	_apply_wood_background()
	_apply_border_style(Color.TRANSPARENT, 0)
	_apply_name_label_style()
	_overlay.color = Color(WOOD_DARK.r, WOOD_DARK.g, WOOD_DARK.b, 0.35)
	_create_info_panel()

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _apply_wood_background() -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = WOOD_SURFACE
	normal.border_color = WOOD_BORDER
	normal.border_width_left = 4
	normal.border_width_right = 4
	normal.border_width_top = 4
	normal.border_width_bottom = 4
	normal.corner_radius_top_left = 10
	normal.corner_radius_top_right = 10
	normal.corner_radius_bottom_right = 10
	normal.corner_radius_bottom_left = 10
	normal.shadow_color = Color(0, 0, 0, 0.4)
	normal.shadow_size = 6
	normal.shadow_offset = Vector2(2, 3)
	normal.content_margin_left = 0
	normal.content_margin_right = 0
	normal.content_margin_top = 0
	normal.content_margin_bottom = 0
	add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate()
	hover.bg_color = WOOD_HOVER
	hover.shadow_size = 8
	hover.shadow_offset = Vector2(2, 4)
	add_theme_stylebox_override("hover", hover)

	var pressed := normal.duplicate()
	pressed.bg_color = WOOD_DARK
	pressed.shadow_size = 4
	pressed.shadow_offset = Vector2(1, 1)
	add_theme_stylebox_override("pressed", pressed)

	var focus := normal.duplicate()
	focus.border_color = GOLDEN
	focus.border_width_left = 2
	focus.border_width_right = 2
	focus.border_width_top = 2
	focus.border_width_bottom = 2
	add_theme_stylebox_override("focus", focus)

func _apply_border_style(color: Color, width: int) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = color
	style.border_width_left = width
	style.border_width_right = width
	style.border_width_top = width
	style.border_width_bottom = width
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_right = 10
	style.corner_radius_bottom_left = 10
	_border.add_theme_stylebox_override("panel", style)

func _apply_name_label_style() -> void:
	_name_label.add_theme_font_override("font", PIXEL_FONT)
	_name_label.add_theme_font_size_override("font_size", WoodPanel.SIZE_CARD_NAME)
	_name_label.add_theme_color_override("font_color", TEXT_COLOR)
	_name_label.add_theme_color_override("font_shadow_color", Color(WOOD_DARK.r, WOOD_DARK.g, WOOD_DARK.b, 0.9))
	_name_label.add_theme_constant_override("shadow_offset_x", 1)
	_name_label.add_theme_constant_override("shadow_offset_y", 2)

func _create_info_panel() -> void:
	_info_label = Label.new()
	_info_label.name = "InfoLabel"
	_info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_info_label.clip_text = false
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.add_theme_font_override("font", PIXEL_FONT)
	_info_label.add_theme_font_size_override("font_size", WoodPanel.SIZE_CARD_DETAIL)
	_info_label.add_theme_color_override("font_color", PARCHMENT_DARK)
	add_child(_info_label)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = PARCHMENT_BG
	panel_style.border_color = PARCHMENT_DARK
	panel_style.border_width_left = 1
	panel_style.border_width_right = 1
	panel_style.border_width_top = 1
	panel_style.border_width_bottom = 1
	panel_style.corner_radius_top_left = 6
	panel_style.corner_radius_top_right = 6
	panel_style.corner_radius_bottom_right = 6
	panel_style.corner_radius_bottom_left = 6
	panel_style.content_margin_left = 8
	panel_style.content_margin_right = 8
	panel_style.content_margin_top = 4
	panel_style.content_margin_bottom = 4
	_info_label.add_theme_stylebox_override("normal", panel_style)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_info_panel()

func _layout_info_panel() -> void:
	if _info_label == null:
		return
	var info_height := 50.0
	_info_label.set_anchor_and_offset(SIDE_LEFT, 0.0, 8)
	_info_label.set_anchor_and_offset(SIDE_RIGHT, 1.0, -8)
	_info_label.set_anchor_and_offset(SIDE_BOTTOM, 1.0, -8)
	_info_label.set_anchor_and_offset(SIDE_TOP, 1.0, -(info_height + 8))

	_name_label.offset_top = -(info_height + 44)
	_name_label.offset_bottom = -info_height - 8
	_name_label.offset_left = 8
	_name_label.offset_right = -8

func _on_mouse_entered() -> void:
	_is_hovered = true
	if not _is_selected:
		_tween_scale(HOVER_SCALE)

func _on_mouse_exited() -> void:
	_is_hovered = false
	_tween_scale(1.0)

func _tween_scale(target: float) -> void:
	var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(self, "scale", Vector2(target, target), 0.15)
	tw.play()

func set_world(id: String, world_name: String, thumbnail: Texture2D = null, info: Dictionary = {}) -> void:
	world_id = id
	if _name_label != null:
		_name_label.text = world_name
	if _thumbnail != null and thumbnail != null:
		_thumbnail.texture = thumbnail
	set_world_info(info)

func set_world_info(info: Dictionary) -> void:
	if _info_label == null:
		return
	if info.is_empty():
		_info_label.text = ""
		_info_label.visible = false
		return
	_info_label.visible = true
	var lines: PackedStringArray = []
	if info.has("created_at"):
		lines.append("Created: %s" % str(info["created_at"]))
	if info.has("season"):
		lines.append("Season: %s" % str(info["season"]))
	if info.has("play_time"):
		lines.append("Played: %s" % str(info["play_time"]))
	if info.has("day"):
		lines.append("Day: %s" % str(info["day"]))
	if info.has("population"):
		lines.append("Population: %s" % str(info["population"]))
	_info_label.text = "\n".join(lines)

func set_selected(selected: bool) -> void:
	_is_selected = selected
	if selected:
		_apply_border_style(GOLDEN, 5)
		_border.visible = true
		_apply_selected_background()
		_tween_scale(1.0)
	else:
		_apply_border_style(Color.TRANSPARENT, 0)
		_border.visible = false
		_apply_wood_background()
		if _is_hovered:
			_tween_scale(HOVER_SCALE)

func _apply_selected_background() -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = WOOD_HOVER
	normal.border_color = GOLDEN
	normal.border_width_left = 5
	normal.border_width_right = 5
	normal.border_width_top = 5
	normal.border_width_bottom = 5
	normal.corner_radius_top_left = 10
	normal.corner_radius_top_right = 10
	normal.corner_radius_bottom_right = 10
	normal.corner_radius_bottom_left = 10
	normal.shadow_color = Color(GOLDEN.r, GOLDEN.g, GOLDEN.b, 0.3)
	normal.shadow_size = 10
	normal.shadow_offset = Vector2(2, 4)
	normal.content_margin_left = 0
	normal.content_margin_right = 0
	normal.content_margin_top = 0
	normal.content_margin_bottom = 0
	add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate()
	hover.bg_color = Color(WOOD_HOVER.r + 0.05, WOOD_HOVER.g + 0.05, WOOD_HOVER.b + 0.05)
	hover.shadow_size = 12
	add_theme_stylebox_override("hover", hover)

	var pressed := normal.duplicate()
	pressed.bg_color = WOOD_DARK
	pressed.shadow_size = 6
	add_theme_stylebox_override("pressed", pressed)
