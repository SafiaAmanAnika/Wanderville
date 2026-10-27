extends RefCounted
## Shared social, wardrobe, settings and gameplay HUD design language.
const INK := Color("382820")
const PAPER := Color("f5e7d3")
const MAROON := Color("85353e")
const SAGE := Color("627c59")
const EDGE := Color("c79a75")
const FONT := preload("res://Assets/fonts/DynaPuff.res")
const BODY_FONT := preload("res://Assets/fonts/Nunito.res")
const WALNUT := Color("38291f")
static var _body: FontVariation

static func body_font() -> Font:
	if _body == null:
		_body = FontVariation.new()
		_body.base_font = BODY_FONT
		_body.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600.0}
	return _body

static func hud_box() -> StyleBox:
	var style := UiSkin.card()
	style.content_margin_left = 20
	style.content_margin_right = 20
	return style

static func box(color: Color = PAPER, margin: int = 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = EDGE
	s.set_border_width_all(2)
	s.set_corner_radius_all(3)
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin
	s.content_margin_bottom = margin
	return s

static func theme() -> Theme:
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = 20
	for type in ["Label", "Button", "LineEdit", "OptionButton", "MenuButton", "ItemList", "RichTextLabel"]:
		t.set_color("font_color", type, INK)
	t.set_color("default_color", "RichTextLabel", INK)
	t.set_color("font_placeholder_color", "LineEdit", Color("9a7d63"))
	# Panels, buttons and fields wear the supplied UI pack (UiSkin).
	for type in ["PanelContainer", "Panel"]:
		t.set_stylebox("panel", type, UiSkin.card())
	for type in ["Button", "OptionButton", "MenuButton"]:
		for state in ["normal", "hover", "pressed", "disabled"]:
			t.set_stylebox(state, type, UiSkin.button(state))
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_color("font_pressed_color", type, UiSkin.CREAM)
		t.set_color("font_hover_color", type, UiSkin.CREAM)
		t.set_color("font_hover_pressed_color", type, UiSkin.CREAM)
		t.set_color("font_focus_color", type, INK)
		t.set_color("font_disabled_color", type, Color("9a8472"))
	for type in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", type, UiSkin.input())
		t.set_stylebox("focus", type, UiSkin.input(true))
	# ItemList draws its box as "panel"; RichTextLabel as "normal".
	t.set_stylebox("panel", "ItemList", UiSkin.card())
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	t.set_color("font_color", "ItemList", INK)
	t.set_color("font_selected_color", "ItemList", INK)
	t.set_color("font_hovered_color", "ItemList", INK)
	t.set_stylebox("normal", "RichTextLabel", UiSkin.card())
	t.set_stylebox("focus", "RichTextLabel", UiSkin.card())
	t.set_stylebox("selected", "ItemList", box(Color("e5c399"), 4))
	t.set_stylebox("selected_focus", "ItemList", box(Color("e5c399"), 4))
	t.set_stylebox("scroll", "VScrollBar", box(Color("ead2b2"), 0))
	t.set_stylebox("grabber", "VScrollBar", box(SAGE, 0))
	return t

static func button(text: String, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.theme = theme()
	b.custom_minimum_size.y = 36
	if primary:
		UiSkin.apply_buy_sell_button(b)
	return b

static func label(text: String, size: int = 20) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT if size >= 28 else body_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", INK)
	return l

static func apply_tree(node: Node) -> void:
	if node is Control:
		node.theme = theme()
		if node is Label or node is BaseButton or node is LineEdit or node is TextEdit:
			node.add_theme_font_override("font", body_font())
		if node is RichTextLabel: node.add_theme_font_override("normal_font", body_font())
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_placeholder_color"]:
			node.remove_theme_color_override(key)
		for key in ["normal", "hover", "pressed", "disabled", "focus", "panel"]:
			node.remove_theme_stylebox_override(key)
		if node is Label:
			node.add_theme_color_override("font_color", INK)
		if node is RichTextLabel:
			node.add_theme_color_override("default_color", INK)
	for child in node.get_children():
		apply_tree(child)
