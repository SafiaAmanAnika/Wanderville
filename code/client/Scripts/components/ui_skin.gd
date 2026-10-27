class_name UiSkin
extends RefCounted
## Nine-patch styles cut from the supplied UI pack.
##
## The textures in Assets/ui/skin are built by Assets/ui/build_skin.py. Each
## texture margin covers that piece's frame, rounded corner and copper rivets,
## and on the buttons and shop card also the flower in the bottom-right corner,
## so a stretched box never smears them. Rebuild the PNGs and re-measure these
## margins together.

const INK := Color(0.30, 0.19, 0.09)        ## text on parchment
const INK_SOFT := Color(0.48, 0.34, 0.20)   ## secondary text on parchment
const CREAM := Color(1.0, 0.95, 0.85)       ## text on the maroon pieces
const GOLD_TINT := Color(1.0, 0.84, 0.58)   ## a selected card or slot
const HOVER_TINT := Color(1.0, 0.95, 0.86)
const PARCHMENT := Color8(251, 233, 194)    ## the panel art's face, for flat fills

const PANEL := preload("res://Assets/ui/skin/panel.png")
const BUTTON_NORMAL := preload("res://Assets/ui/skin/button_normal.png")
const BUTTON_HOVER := preload("res://Assets/ui/skin/button_hover.png")
const BUTTON_PRESSED := preload("res://Assets/ui/skin/button_pressed.png")
const BUTTON_DISABLED := preload("res://Assets/ui/skin/button_disabled.png")
const INPUT := preload("res://Assets/ui/skin/input.png")
const MESSAGE_STRIP := preload("res://Assets/ui/skin/message_strip.png")
const CARD := preload("res://Assets/ui/skin/card.png")
const SLOT := preload("res://Assets/ui/skin/slot.png")
const SHOP_CARD := preload("res://Assets/ui/skin/shop_card.png")
const WORLD_CARD := preload("res://Assets/ui/skin/world_card.png")
const FLOOR_SWATCH := preload("res://Assets/ui/skin/floor_swatch.png")
const BUY_SELL := preload("res://Assets/ui/skin/buy_sell.png")
const PROGRESS_TRACK := preload("res://Assets/ui/skin/progress_track.png")
const PROGRESS_FILL := preload("res://Assets/ui/skin/progress_fill.png")
const SETTINGS_ICON := preload("res://Assets/ui/skin/settings_icon.png")
const QUANTITY_MINUS := preload("res://Assets/ui/skin/quantity_minus.png")
const QUANTITY_PLUS := preload("res://Assets/ui/skin/quantity_plus.png")


## margins and content are [left, right, top, bottom].
static func _box(texture: Texture2D, margins: Array, content: Array,
		tint := Color.WHITE) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = texture
	box.texture_margin_left = margins[0]
	box.texture_margin_right = margins[1]
	box.texture_margin_top = margins[2]
	box.texture_margin_bottom = margins[3]
	box.content_margin_left = content[0]
	box.content_margin_right = content[1]
	box.content_margin_top = content[2]
	box.content_margin_bottom = content[3]
	box.modulate_color = tint
	return box


static func panel() -> StyleBoxTexture:
	return _box(PANEL, [54, 54, 54, 54], [36, 36, 38, 38])


static func card(tint := Color.WHITE) -> StyleBoxTexture:
	return _box(CARD, [16, 16, 17, 17], [16, 16, 14, 14], tint)


static func slot(tint := Color.WHITE) -> StyleBoxTexture:
	return _box(SLOT, [17, 17, 14, 18], [14, 14, 12, 14], tint)


static func shop_card(tint := Color.WHITE) -> StyleBoxTexture:
	return _box(SHOP_CARD, [30, 37, 30, 41], [18, 20, 16, 18], tint)


static func world_card(tint := Color.WHITE) -> StyleBoxTexture:
	return _box(WORLD_CARD, [22, 21, 20, 25], [20, 20, 18, 20], tint)


static func floor_swatch(tint := Color.WHITE) -> StyleBoxTexture:
	return _box(FLOOR_SWATCH, [8, 8, 8, 8], [6, 6, 6, 6], tint)


static func input(focused := false) -> StyleBoxTexture:
	return _box(INPUT, [11, 11, 10, 8], [14, 14, 8, 8], HOVER_TINT if focused else Color.WHITE)


static func input_error() -> StyleBoxTexture:
	return _box(INPUT, [11, 11, 10, 8], [14, 14, 8, 8], Color(1.0, 0.72, 0.68))


static func message_strip() -> StyleBoxTexture:
	return _box(MESSAGE_STRIP, [16, 16, 14, 11], [28, 28, 10, 10])


static func buy_sell() -> StyleBoxTexture:
	return _box(BUY_SELL, [14, 14, 12, 12], [14, 14, 8, 8])


static func progress_track() -> StyleBoxTexture:
	return _box(PROGRESS_TRACK, [7, 7, 4, 4], [0, 0, 0, 0])


static func progress_fill() -> StyleBoxTexture:
	return _box(PROGRESS_FILL, [6, 6, 3, 3], [0, 0, 0, 0])


## "normal", "hover", "pressed" or "disabled".
static func button(state := "normal") -> StyleBoxTexture:
	var texture: Texture2D = {
		"hover": BUTTON_HOVER, "pressed": BUTTON_PRESSED, "disabled": BUTTON_DISABLED,
	}.get(state, BUTTON_NORMAL)
	return _box(texture, [15, 23, 14, 26], [18, 22, 9, 12])


## Dress any Button in the pack's four states and matching text colours.
static func apply_button(target: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		target.add_theme_stylebox_override(state, button(state))
	target.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	target.add_theme_color_override("font_color", INK)
	target.add_theme_color_override("font_focus_color", INK)
	target.add_theme_color_override("font_hover_color", CREAM)
	target.add_theme_color_override("font_pressed_color", CREAM)
	target.add_theme_color_override("font_hover_pressed_color", CREAM)
	target.add_theme_color_override("font_disabled_color", Color(INK_SOFT, 0.6))


## A button that is one picture from the pack, tinted for hover/press/disabled.
static func apply_icon_button(target: Button, texture: Texture2D) -> void:
	var none := [0, 0, 0, 0]
	target.text = ""
	target.add_theme_stylebox_override("normal", _box(texture, none, none))
	target.add_theme_stylebox_override("hover", _box(texture, none, none, HOVER_TINT))
	target.add_theme_stylebox_override("pressed", _box(texture, none, none, GOLD_TINT))
	target.add_theme_stylebox_override("disabled", _box(texture, none, none, Color(1, 1, 1, 0.45)))
	target.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


## The pack's −/+ tiles. The art carries the sign, so the text is dropped.
static func apply_quantity_button(target: Button, plus: bool) -> void:
	apply_icon_button(target, QUANTITY_PLUS if plus else QUANTITY_MINUS)


## The maroon Buy / Sell plank.
static func apply_buy_sell_button(target: Button) -> void:
	var base := buy_sell()
	target.add_theme_stylebox_override("normal", base)
	target.add_theme_stylebox_override("hover", _box(BUY_SELL, [14, 14, 12, 12], [14, 14, 8, 8], Color(1.15, 1.1, 1.1)))
	target.add_theme_stylebox_override("pressed", _box(BUY_SELL, [14, 14, 12, 12], [14, 14, 8, 8], Color(0.85, 0.8, 0.8)))
	target.add_theme_stylebox_override("disabled", _box(BUY_SELL, [14, 14, 12, 12], [14, 14, 8, 8], Color(0.75, 0.7, 0.7, 0.55)))
	target.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		target.add_theme_color_override(key, CREAM)
	target.add_theme_color_override("font_disabled_color", Color(CREAM, 0.6))


static func apply_progress_bar(bar: ProgressBar) -> void:
	bar.add_theme_stylebox_override("background", progress_track())
	bar.add_theme_stylebox_override("fill", progress_fill())


static var _dialog_theme: Theme

## Theme for Window-based popups (AcceptDialog, ConfirmationDialog, Window):
## the pack's panel frame drawn around the title bar and body, ink title and
## text, and an ink close cross. Buttons still come from the project theme.
static func dialog_theme() -> Theme:
	if _dialog_theme != null:
		return _dialog_theme
	var t := Theme.new()
	var title_height := 40
	for key in ["embedded_border", "embedded_unfocused_border"]:
		# The border is drawn outside the window's client area, and above it
		# by the title bar, so the frame grows outward by expand margins.
		var frame := panel()
		frame.expand_margin_left = 34
		frame.expand_margin_right = 34
		frame.expand_margin_top = title_height + 30
		frame.expand_margin_bottom = 34
		t.set_stylebox(key, "Window", frame)
	t.set_constant("title_height", "Window", title_height)
	t.set_font("title_font", "Window", WoodPanel.PIXEL_FONT)
	t.set_font_size("title_font_size", "Window", WoodPanel.SIZE_STATUS + 4)
	t.set_color("title_color", "Window", INK)
	t.set_constant("title_outline_size", "Window", 0)
	var cross := _close_icon()
	t.set_icon("close", "Window", cross)
	t.set_icon("close_pressed", "Window", cross)
	t.set_constant("close_h_offset", "Window", 22)
	t.set_constant("close_v_offset", "Window", 22)
	# An embedded window does not show its frame through the client area, so
	# the body is filled with the panel art's own parchment colour.
	var body := StyleBoxFlat.new()
	body.bg_color = PARCHMENT
	body.set_content_margin_all(6)
	t.set_stylebox("panel", "AcceptDialog", body)
	t.set_constant("buttons_separation", "AcceptDialog", 14)
	t.set_color("font_color", "Label", INK)
	_dialog_theme = t
	return t


## Dress a popup window and everything inside it.
static func apply_dialog(window: Window) -> void:
	window.theme = dialog_theme()
	# AcceptDialog paints its body with the theme's "panel"; a plain Window
	# paints nothing, so it gets a parchment backdrop behind its contents.
	if not window is AcceptDialog and not window.has_node("ParchmentBackdrop"):
		var backdrop := Panel.new()
		backdrop.name = "ParchmentBackdrop"
		backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fill := StyleBoxFlat.new()
		fill.bg_color = PARCHMENT
		backdrop.add_theme_stylebox_override("panel", fill)
		window.add_child(backdrop)
		window.move_child(backdrop, 0)
		backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


static func _close_icon() -> Texture2D:
	var size := 16
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for i in range(2, size - 2):
		for offset in [-1, 0, 1]:
			for point in [Vector2i(i, i + offset), Vector2i(i, size - 1 - i + offset)]:
				if point.y >= 0 and point.y < size:
					image.set_pixelv(point, INK)
	return ImageTexture.create_from_image(image)


static var _text_theme: Theme

## Dark ink for every text control that has not chosen its own colour. Set on
## a skinned panel, it reaches everything inside, so labels laid out in scenes
## without colours stop falling back to Godot's default white on parchment.
static func text_theme() -> Theme:
	if _text_theme != null:
		return _text_theme
	var t := Theme.new()
	for type in ["Label", "CheckBox", "CheckButton", "LinkButton"]:
		t.set_color("font_color", type, INK)
		t.set_color("font_shadow_color", type, Color.TRANSPARENT)
		t.set_constant("outline_size", type, 0)
	for type in ["CheckBox", "CheckButton", "LinkButton"]:
		t.set_color("font_hover_color", type, INK_SOFT)
		t.set_color("font_pressed_color", type, INK)
		t.set_color("font_focus_color", type, INK)
		t.set_color("font_hover_pressed_color", type, INK)
	t.set_color("default_color", "RichTextLabel", INK)
	t.set_color("font_color", "ItemList", INK)
	t.set_color("font_selected_color", "ItemList", INK)
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", INK_SOFT)
	t.set_color("font_color", "TextEdit", INK)
	_text_theme = t
	return t


## Give a panel's contents dark text unless the panel already has a theme.
static func ink_text(control: Control) -> void:
	if control.theme == null:
		control.theme = text_theme()
