extends AnimatedSprite2D
## Original artwork only; this preview never instantiates a player controller.
const Frames := preload("res://Scripts/chara_frames.gd")
var character := "girl_a"
var action := "idle"
var direction := "front"

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_character(character)

func set_character(code: String) -> void:
	character = code if Global.CHARACTERS.has(code) and Global.CHARACTERS[code].folder != "" else "girl_a"
	set_pose(action, direction)

func set_pose(next_action: String, next_direction: String, next_frame: int = 0) -> void:
	action = next_action if next_action in Frames.ACTIONS else "idle"
	direction = next_direction if next_direction in Frames.DIRECTIONS else "front"
	sprite_frames = Frames.preview_frames(Global.CHARACTERS[character].folder, action)
	play(action + "_" + direction)
	set_frame_and_progress(posmod(next_frame, 6), 0.0)
