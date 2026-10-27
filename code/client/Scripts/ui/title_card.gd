extends Button
## Painted artwork with live text, keyboard focus, and native button interaction.
const Style := preload("res://Scripts/ui/lobby_theme.gd")
const CREAM := preload("res://Assets/ui/title/cream-card.res")
const CUTOUT := preload("res://Assets/ui/title/painted_cutout.gdshader")
const ICON_INK := preload("res://Assets/ui/title/selected_icon.gdshader")
var wood := false
var _art: TextureRect
var _center: CenterContainer
var _caption: Label
var _glyph: TextureRect
var _material: ShaderMaterial
var _icon_material: ShaderMaterial
var _highlight := 0.0
var _highlight_tween: Tween

func configure(caption: String, kind: String, wooden: bool = false, font_size: int = 27) -> void:
	text = caption
	wood = wooden
	theme = Style.theme()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		add_theme_color_override(state, Color.TRANSPARENT)
	_art = TextureRect.new()
	_art.show_behind_parent = true
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_SCALE
	_fill(_art)
	# Discard the generated soft halo while retaining antialiased painted edges.
	_material = ShaderMaterial.new(); _material.shader = CUTOUT; _art.material = _material
	_art.texture = CREAM
	_center = CenterContainer.new(); _fill(_center)
	var row := HBoxContainer.new(); row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 16); _center.add_child(row)
	_glyph = TextureRect.new(); _glyph.texture = icon_texture(kind)
	_icon_material = ShaderMaterial.new(); _icon_material.shader = ICON_INK; _glyph.material = _icon_material
	_glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_glyph.custom_minimum_size = Vector2(34,34); _glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glyph.visible = not kind.is_empty()
	row.add_child(_glyph)
	_caption = Style.label(caption, font_size); _caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.visible = not caption.is_empty(); row.add_child(_caption)
	custom_minimum_size = Vector2(500,112)
	set_active(false, false)

func _fill(control: Control) -> void:
	add_child(control); control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_active(value: bool, animate: bool = true) -> void:
	if _highlight_tween != null: _highlight_tween.kill()
	if animate and is_inside_tree():
		_highlight_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_highlight_tween.tween_method(_set_highlight,_highlight,1.0 if value else 0.0,0.18)
	else: _set_highlight(1.0 if value else 0.0)

func _set_highlight(value: float) -> void:
	_highlight = value
	_material.set_shader_parameter("selection",value)
	_caption.add_theme_color_override("font_color", Color("fff5dc") if wood else Color("572913").lerp(Color("fff5dc"),value))
	_icon_material.set_shader_parameter("selection",value)

func _process(_delta: float) -> void:
	if _art == null: return
	var tint := Color("a46d46") if wood else Color.WHITE
	_art.modulate = tint * (0.92 if is_pressed() else 1.0)
	_caption.modulate.a = 0.58 if disabled else 1.0
	_glyph.modulate.a = 0.58 if disabled else 1.0
	_center.position.y = 2.0 if is_pressed() else 0.0

static func icon_texture(kind: String) -> Texture2D:
	if kind.is_empty(): return null
	var content := ""
	match kind:
		"play": content='<path d="m16 9 25 15-25 15Z" fill="#753d23" stroke="#512918" stroke-width="2" stroke-linejoin="round"/>'
		"settings": content='<g fill="#753d23"><rect x="20" y="3" width="8" height="42" rx="2"/><rect x="3" y="20" width="42" height="8" rx="2"/><rect x="20" y="3" width="8" height="42" rx="2" transform="rotate(45 24 24)"/><rect x="20" y="3" width="8" height="42" rx="2" transform="rotate(-45 24 24)"/><circle cx="24" cy="24" r="16"/></g><circle cx="24" cy="24" r="7" fill="#ffe4ae"/>'
	var image := Image.new()
	image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 48 48">'+content+'</svg>')
	return ImageTexture.create_from_image(image)
