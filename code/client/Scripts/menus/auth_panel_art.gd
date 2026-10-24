extends Control
## Separate ornament layer: fields and links stay native and interactive.
const LOGO := preload("res://Assets/ui/title/logo.res")
var panel: Control
var logo: TextureRect

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	logo=TextureRect.new(); logo.name="AuthLogo"; logo.texture=LOGO
	logo.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter=Control.MOUSE_FILTER_IGNORE; add_child(logo)
	panel.resized.connect(_fit); resized.connect(_fit); _fit()

func _fit() -> void:
	if logo==null: return
	logo.position=Vector2(-40,-166)
	logo.size=Vector2(size.x+80,184)

static func field_icon(password: bool) -> Texture2D:
	var content := '<rect x="4" y="7" width="24" height="18" rx="2" fill="none" stroke="#96724f" stroke-width="3"/><path d="m5 9 11 9 11-9" fill="none" stroke="#96724f" stroke-width="3"/>'
	if password:
		content='<path d="M9 14V9a7 7 0 0 1 14 0v5" fill="none" stroke="#96724f" stroke-width="3"/><rect x="6" y="12" width="20" height="17" rx="3" fill="#96724f"/><circle cx="16" cy="18" r="2" fill="#fff0d8"/><path d="M16 18v5" stroke="#fff0d8" stroke-width="2"/>'
	var image := Image.new()
	image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32">'+content+'</svg>')
	return ImageTexture.create_from_image(image)

static func button_leaves(button: Button) -> void:
	button.draw.connect(func():
		for x in [12.0,button.size.x-12.0]:
			var point := Vector2(x,button.size.y/2)
			for index in 3:
				button.draw_set_transform(point,TAU*index/3)
				var leaf := PackedVector2Array([Vector2(0,0),Vector2(2,-6),Vector2(9,-10),Vector2(12,-8),Vector2(10,-2),Vector2(4,1),Vector2(0,0)])
				button.draw_colored_polygon(leaf,Color("77954c"))
				button.draw_polyline(leaf,Color("40522a"),1.5,true)
				button.draw_line(Vector2(1,0),Vector2(8,-6),Color("b0bf69"),1,true)
			button.draw_set_transform(Vector2.ZERO)
	)
