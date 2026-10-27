class_name WoodPanel
extends PanelContainer

## Reusable wooden board panel for all menu screens.
## Provides the carved-border, warm-brown panel look with parchment accents.

# ── Wood palette ────────────────────────────────────────────────────
const WOOD_DARK := Color(0.28, 0.17, 0.08)
const WOOD_BORDER := Color(0.38, 0.25, 0.13)
const WOOD_FRAME := Color(0.45, 0.30, 0.17)
const WOOD_SURFACE := Color(0.60, 0.43, 0.27)
const WOOD_BASE := Color(0.52, 0.36, 0.22)
const WOOD_HOVER := Color(0.72, 0.56, 0.37)
const WOOD_BEVEL_LIGHT := Color(0.78, 0.62, 0.42)
const WOOD_BEVEL_DARK := Color(0.32, 0.20, 0.10)
const ROPE_COLOR := Color(0.55, 0.45, 0.30)
const ROPE_SHADOW := Color(0.35, 0.25, 0.15)

# ── Text palette ────────────────────────────────────────────────────
const PIXEL_FONT := preload("res://Assets/fonts/BoldPixels.ttf")
const TEXT_COLOR := Color(0.95, 0.91, 0.80)
const TEXT_SECONDARY := Color(0.82, 0.74, 0.58)
const TEXT_ERROR := Color(0.90, 0.38, 0.30)
const TEXT_SUCCESS := Color(0.50, 0.78, 0.45)
const TEXT_PLACEHOLDER := Color(0.60, 0.50, 0.38)

# ── Parchment palette ───────────────────────────────────────────────
const PARCHMENT := Color(0.92, 0.85, 0.68)
const PARCHMENT_DARK := Color(0.80, 0.72, 0.55)
const PARCHMENT_BG := Color(0.85, 0.78, 0.60)

# ── Input palette ───────────────────────────────────────────────────
const INPUT_BG := Color(0.22, 0.15, 0.08)
const INPUT_BORDER := Color(0.50, 0.36, 0.22)

# ── Font sizes (desktop) ───────────────────────────────────────────
const SIZE_TITLE := 36
const SIZE_PANEL_TITLE := 32
const SIZE_BUTTON := 24
const SIZE_FIELD := 22
const SIZE_STATUS := 20
const SIZE_SMALL := 18
const SIZE_CARD_NAME := 24
const SIZE_CARD_DETAIL := 18
const SIZE_BANNER_TITLE := 52
const SIZE_BANNER_SUBTITLE := 22

const CROP_ART = preload("res://Scripts/crop_catalog.gd")

static var _item_icons: Dictionary = {}

static func item_icon(code: String) -> Texture2D:
	if _item_icons.has(code):
		return _item_icons[code]
	# Crops and seeds come from the spritesheet manifest, fish from Assets/fishes.
	# Both resolve a code against a list that ships with the game, so a server
	# string can never be read as an arbitrary resource path.
	var texture: Texture2D = CROP_ART.icon(code)
	if texture == null:
		texture = _fish_icon(code)
	if texture == null:
		var placeholder := AtlasTexture.new()
		placeholder.atlas = preload("res://Assets/inventory/inventorySlot.png")
		placeholder.region = Rect2(0, 0, placeholder.atlas.get_width(), placeholder.atlas.get_height() / 2.0)
		texture = placeholder
	_item_icons[code] = texture
	return texture


## One fish's picture, or null when the code is not a fish this build knows.
static func _fish_icon(code: String) -> Texture2D:
	if not ItemCatalog.FISH.has(code):
		return null
	var path := "res://Assets/fishes/%s.png" % code
	if not ResourceLoader.exists(path):
		# river_carp and golden_carp are server fish with no art of their own,
		# so they borrow the plain carp until someone draws them.
		path = "res://Assets/fishes/carp.png"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _ready() -> void:
	_apply_panel_style()


func _apply_panel_style() -> void:
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


# ── Static label styles ─────────────────────────────────────────────

static func apply_title_style(label: Label) -> void:
	if label == null:
		return
	label.add_theme_font_override("font", PIXEL_FONT)
	label.add_theme_font_size_override("font_size", SIZE_TITLE)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


static func apply_panel_title_style(label: Label) -> void:
	if label == null:
		return
	label.add_theme_font_override("font", PIXEL_FONT)
	label.add_theme_font_size_override("font_size", SIZE_PANEL_TITLE)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


static func apply_subtitle_style(label: Label) -> void:
	if label == null:
		return
	label.add_theme_font_override("font", PIXEL_FONT)
	label.add_theme_font_size_override("font_size", SIZE_SMALL)
	label.add_theme_color_override("font_color", TEXT_SECONDARY)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


static func apply_status_label(label: Label) -> void:
	if label == null:
		return
	label.add_theme_font_override("font", PIXEL_FONT)
	label.add_theme_font_size_override("font_size", SIZE_STATUS)
	label.add_theme_color_override("font_color", TEXT_SECONDARY)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


static func apply_error_label(label: Label) -> void:
	if label == null:
		return
	label.add_theme_font_override("font", PIXEL_FONT)
	label.add_theme_font_size_override("font_size", SIZE_STATUS)
	label.add_theme_color_override("font_color", TEXT_ERROR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


static func apply_card_name_style(label: Label) -> void:
	if label == null:
		return
	label.add_theme_font_override("font", PIXEL_FONT)
	label.add_theme_font_size_override("font_size", SIZE_CARD_NAME)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


static func apply_card_detail_style(label: Label) -> void:
	if label == null:
		return
	label.add_theme_font_override("font", PIXEL_FONT)
	label.add_theme_font_size_override("font_size", SIZE_CARD_DETAIL)
	label.add_theme_color_override("font_color", TEXT_SECONDARY)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


# ── Static field styles ─────────────────────────────────────────────

static func apply_field_style(edit: LineEdit) -> void:
	if edit == null:
		return
	edit.add_theme_font_override("font", PIXEL_FONT)
	edit.add_theme_font_size_override("font_size", SIZE_FIELD)
	edit.add_theme_color_override("font_color", TEXT_COLOR)
	edit.add_theme_color_override("font_placeholder_color", TEXT_PLACEHOLDER)

	var sb := StyleBoxFlat.new()
	sb.bg_color = INPUT_BG
	sb.border_color = INPUT_BORDER
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	edit.add_theme_stylebox_override("normal", sb)

	var focus_sb := StyleBoxFlat.new()
	focus_sb.bg_color = INPUT_BG
	focus_sb.border_color = Color(0.75, 0.60, 0.38)
	focus_sb.set_border_width_all(3)
	focus_sb.set_corner_radius_all(6)
	focus_sb.content_margin_left = 12
	focus_sb.content_margin_right = 12
	focus_sb.content_margin_top = 10
	focus_sb.content_margin_bottom = 10
	edit.add_theme_stylebox_override("focus", focus_sb)


static func apply_error_field_style(edit: LineEdit) -> void:
	if edit == null:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.35, 0.15, 0.12)
	sb.border_color = Color(0.85, 0.30, 0.25)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	edit.add_theme_stylebox_override("normal", sb)


static func clear_error_field_style(edit: LineEdit) -> void:
	if edit == null:
		return
	edit.remove_theme_stylebox_override("normal")
	apply_field_style(edit)


# ── Parchment style helpers ─────────────────────────────────────────

static func make_parchment_style(margin: int = 20) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PARCHMENT_BG
	sb.border_color = PARCHMENT_DARK
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin
	sb.content_margin_bottom = margin
	return sb


static func apply_parchment_label(label: Label, font_size: int = SIZE_STATUS) -> void:
	if label == null:
		return
	label.add_theme_font_override("font", PIXEL_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.30, 0.22, 0.12))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


# ── Wooden card style helpers ───────────────────────────────────────

static func make_wood_card_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = WOOD_SURFACE
	sb.border_color = WOOD_BORDER
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(10)
	sb.shadow_color = Color(0.10, 0.05, 0.01, 0.5)
	sb.shadow_size = 5
	sb.shadow_offset = Vector2(2, 3)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	return sb


static func make_wood_card_hover_style() -> StyleBoxFlat:
	var sb := make_wood_card_style()
	sb.bg_color = WOOD_HOVER
	sb.border_color = WOOD_BEVEL_LIGHT
	sb.shadow_size = 6
	return sb


static func make_wood_card_selected_style() -> StyleBoxFlat:
	var sb := make_wood_card_style()
	sb.bg_color = WOOD_HOVER
	sb.border_color = Color(1.0, 0.84, 0.0)
	sb.set_border_width_all(5)
	sb.shadow_size = 8
	return sb


# ── Dialog overlay style ────────────────────────────────────────────

static func make_overlay_color() -> Color:
	return Color(0.05, 0.03, 0.01, 0.7)


static func make_dialog_panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = WOOD_FRAME
	sb.border_color = WOOD_DARK
	sb.border_width_left = 8
	sb.border_width_right = 8
	sb.border_width_top = 8
	sb.border_width_bottom = 8
	sb.set_corner_radius_all(14)
	sb.shadow_color = Color(0.05, 0.02, 0.0, 0.8)
	sb.shadow_size = 12
	sb.shadow_offset = Vector2(4, 6)
	sb.content_margin_left = 32
	sb.content_margin_right = 32
	sb.content_margin_top = 28
	sb.content_margin_bottom = 28
	return sb


# ── Viewport helper ─────────────────────────────────────────────────

static func get_viewport_size() -> Vector2:
	var vp_size := Vector2(1578, 997)
	if Engine.has_singleton("DisplayServer"):
		vp_size = Vector2(
			DisplayServer.window_get_size().x,
			DisplayServer.window_get_size().y
		)
	return vp_size


static func center_control(control: Control) -> void:
	var vp := control.get_viewport_rect().size
	control.position = (vp - control.size) / 2.0


# ── Entrance animation helper ───────────────────────────────────────

static func play_entrance(panel: Control, delay: float = 0.0) -> Tween:
	if panel == null:
		return null
	panel.modulate.a = 0.0
	var tw := panel.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(panel, "modulate:a", 1.0, 0.4)
	return tw
