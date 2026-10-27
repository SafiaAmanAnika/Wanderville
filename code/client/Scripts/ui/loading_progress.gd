extends Control
## Shared loading indicator. Negative progress means the work has no known total.
const Style := preload("res://Scripts/ui/lobby_theme.gd")
const CAT := preload("res://Assets/ui/title/selection-cat.res")
const CAPTION := "Purring..."
var message: Label
var progress := -1.0
var _elapsed := 0.0
var _cat: TextureRect
var _watched: Label

static func attach(label: Label) -> Control:
	var indicator := load("res://Scripts/ui/loading_progress.gd").new() as Control
	indicator.set("_watched",label)
	indicator.name = "SharedLoadingProgress"
	indicator.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var parent := label.get_parent()
	parent.add_child(indicator); parent.move_child(indicator,label.get_index()+1)
	indicator.get("message").add_theme_font_size_override("font_size",18)
	indicator.hide()
	return indicator

func _ready() -> void:
	custom_minimum_size = Vector2(0,104)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	message = Style.label(CAPTION,22)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(message)
	_cat = TextureRect.new(); _cat.texture = CAT
	_cat.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cat.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_cat.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_cat.size = Vector2(72,48); _cat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cat)
	resized.connect(_layout); _layout()

func _layout() -> void:
	if message == null: return
	message.position = Vector2(0,0); message.size = Vector2(size.x,30)
	_place_cat()

func start(_text: String) -> void:
	message.text = CAPTION; progress = -1.0; _elapsed = 0.0; queue_redraw()

func set_progress(value: float) -> void:
	progress = clampf(value,0.0,1.0); queue_redraw()

func _process(delta: float) -> void:
	if is_instance_valid(_watched):
		var text := _watched.text.strip_edges()
		var waiting := false
		for prefix in ["Loading", "Logging in", "Opening Google", "Continue in your browser", "Creating account", "Sending reset", "Verifying...", "Resetting password", "Saving", "Please wait", "Connecting", "Reconnecting"]:
			if text.begins_with(prefix): waiting = true; break
		if waiting:
			message.text = CAPTION; show(); _watched.hide()
		else:
			if visible: _watched.visible = not text.is_empty()
			hide()
	if not is_visible_in_tree(): return
	_elapsed += delta
	_place_cat()
	queue_redraw()

func _place_cat() -> void:
	if _cat == null: return
	var ratio := progress if progress >= 0 else 0.28+0.72*(0.5-0.5*cos(_elapsed*2.2))
	_cat.position = Vector2(18+(size.x-36)*ratio-36,26)

func _draw() -> void:
	var width := maxf(40,size.x-36)
	var frame := Rect2(16,65,width+4,24)
	var rim := Style.box(Color("f9e7c7"),0)
	rim.border_color = Color("633c27"); rim.set_corner_radius_all(11)
	draw_style_box(rim,frame)
	var track := Rect2(20,69,width-4,16)
	var track_style := Style.box(Color("d4b995"),0); track_style.set_border_width_all(0); track_style.set_corner_radius_all(8)
	draw_style_box(track_style,track)
	var ratio := progress if progress >= 0 else 0.5-0.33*cos(_elapsed*2.2)
	var fill := track
	if progress < 0:
		fill.position.x += (track.size.x-track.size.x*0.28)*((ratio-0.17)/0.66)
		fill.size.x *= 0.28
	else: fill.size.x *= ratio
	if fill.size.x > 0:
		var fill_style := Style.box(Style.MAROON,0); fill_style.set_border_width_all(0); fill_style.set_corner_radius_all(8)
		draw_style_box(fill_style,fill)
		if fill.size.x>8: draw_line(fill.position+Vector2(5,3),fill.position+Vector2(fill.size.x-5,3),Color("b3686c"),2,true)
	for point in [Vector2(12,77),Vector2(size.x-12,77)]:
		var leaf := Style.box(Color("789b46"),0); leaf.border_color=Color("42592d"); leaf.set_border_width_all(1); leaf.set_corner_radius_all(4)
		draw_set_transform(point,-0.6,Vector2.ONE)
		draw_style_box(leaf,Rect2(-8,-12,6,12)); draw_set_transform(point,0.6,Vector2.ONE)
		draw_style_box(leaf,Rect2(0,-1,6,12)); draw_set_transform(Vector2.ZERO)
		for index in 5:
			var petal: Vector2 = point+Vector2(4,0).rotated(index*TAU/5)
			draw_circle(petal,3,Color("fff1d7"))
		draw_circle(point,2.5,Color("dba843"))
