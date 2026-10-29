extends CanvasLayer
## One persistent player keeps title/auth video playback continuous across routes.
const BG := preload("res://Assets/background/bg.webp")
var player: VideoStreamPlayer
var village: TextureRect
var dim: ColorRect
var _owner_id := 0

static func add_background(parent: Node) -> TextureRect:
	var background := TextureRect.new()
	background.name = "JourneyBackground"; background.texture = BG
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.offset_left=-48; background.offset_top=-48
	background.offset_right=48; background.offset_bottom=48
	return background

func _ready() -> void:
	layer = -30
	var screen := Control.new(); add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	village = add_background(screen)
	player = VideoStreamPlayer.new(); player.name = "AtmosphereVideo"
	player.expand = true; player.loop = true; player.volume_db = -80
	_full(player,screen); player.hide()
	dim=ColorRect.new(); dim.color=Color(0.08,0.06,0.04,0); _full(dim,screen)
	hide()

func _full(control: Control,parent: Node) -> void:
	parent.add_child(control); control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.mouse_filter=Control.MOUSE_FILTER_IGNORE

func present(owner: Node,darkness: float,stream: VideoStream=null) -> void:
	_owner_id=owner.get_instance_id()
	owner.tree_exiting.connect(_release.bind(_owner_id),CONNECT_ONE_SHOT)
	if stream != null and player.stream != stream:
		player.stream=stream; player.show(); player.play()
	player.paused=false; dim.color.a=darkness; show()

func _release(owner_id: int) -> void:
	if _owner_id != owner_id: return
	hide(); player.paused=true
