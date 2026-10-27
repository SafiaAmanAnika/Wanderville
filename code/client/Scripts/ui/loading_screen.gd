extends Control
## Unfiltered original scenery, supplied logo, and the shared cat progress bar.
const Progress := preload("res://Scripts/ui/loading_progress.gd")
const LOGO := preload("res://Assets/ui/title/logo.res")
const Backdrop := preload("res://Scripts/menus/journey_backdrop.gd")
var background: TextureRect
var message: Label
var bar: Control
var composition: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background=Backdrop.add_background(self)
	composition=Control.new(); composition.mouse_filter=Control.MOUSE_FILTER_IGNORE; add_child(composition)
	var logo := TextureRect.new(); logo.texture=LOGO
	logo.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.position=Vector2(20,0); logo.size=Vector2(760,254)
	logo.mouse_filter=Control.MOUSE_FILTER_IGNORE; composition.add_child(logo)
	bar=Progress.new(); bar.position=Vector2(110,280); bar.size=Vector2(580,104); composition.add_child(bar)
	message=bar.message
	message.add_theme_color_override("font_color",Color("fff1d7"))
	message.add_theme_color_override("font_shadow_color",Color("482b20"))
	message.add_theme_constant_override("shadow_offset_x",2); message.add_theme_constant_override("shadow_offset_y",2)
	get_viewport().size_changed.connect(_fit); _fit()

func start(text: String) -> void:
	bar.start(text)

func set_progress(value: float) -> void:
	bar.set_progress(value)

func _fit() -> void:
	var viewport := get_viewport_rect().size
	var factor := minf(1.1,minf((viewport.x-32)/800.0,(viewport.y-32)/400.0))
	composition.size=Vector2(800,400); composition.scale=Vector2.ONE*maxf(0.1,factor)
	composition.position=(viewport-composition.size*composition.scale)/2
