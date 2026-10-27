extends AnimatedSprite2D
## Original artwork only; this preview never instantiates a player controller.
const Frames := preload("res://Scripts/chara_frames.gd")
var character := "girl_a"
var action := "idle"
var direction := "front"
static var _legacy: SpriteFrames

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_character(character)

func set_character(code: String) -> void:
	character = code if Global.CHARACTERS.has(code) else "girl_a"
	set_pose(action, direction)

func set_pose(next_action: String, next_direction: String, next_frame: int = 0) -> void:
	action = next_action if next_action in Frames.ACTIONS else "idle"
	direction = next_direction if next_direction in Frames.DIRECTIONS else "front"
	var folder: String=Global.CHARACTERS[character].folder
	sprite_frames = Frames.preview_frames(folder, action) if not folder.is_empty() else _legacy_frames()
	if folder.is_empty() and action not in ["idle","walk","run"]: action="idle"
	play(action + "_" + direction)
	set_frame_and_progress(posmod(next_frame, sprite_frames.get_frame_count(animation)), 0.0)

static func _legacy_frames() -> SpriteFrames:
	if _legacy!=null: return _legacy
	var sprite: AnimatedSprite2D=load("res://Scenes/girl.tscn").instantiate()
	var source := sprite.sprite_frames
	_legacy=SpriteFrames.new(); _legacy.remove_animation("default")
	var old_dirs := ["south","south_east","east","north_east","north","north_west","west","south_west"]
	for index in 8:
		for next_action in ["idle","walk","run"]:
			var name: String = next_action+"_"+Frames.DIRECTIONS[index]
			var old_name: String = "run_"+old_dirs[index]
			_legacy.add_animation(name); _legacy.set_animation_speed(name,3 if next_action=="walk" else 5)
			var count := 1 if next_action=="idle" else source.get_frame_count(old_name)
			for frame in count: _legacy.add_frame(name,source.get_frame_texture(old_name,frame))
	sprite.free()
	return _legacy
