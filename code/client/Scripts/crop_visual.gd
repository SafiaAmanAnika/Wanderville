# Scripts/crop_visual.gd
#
# Attach this to the AnimatedSprite2D of a crop scene (e.g. paddy.tscn).
# Assumes the "default" animation has 5 frames sliced from the spritesheet:
#   frame 0 = freshly planted seed (dry, no water yet)
#   frame 1..4 = growth stages
#
# Behavior:
#   - Frame 0 is held FOREVER until `water_particles` becomes true.
#   - Once watered, frames 1-4 play in order, each held for its own
#     duration from `frame_durations`.
#   - Emits `fully_grown` when frame 4 (the last frame) is reached.
extends AnimatedSprite2D
class_name CropVisual

# Time (seconds) to hold each frame AFTER frame 0, in order:
# [frame1_duration, frame2_duration, frame3_duration, frame4_duration]
@export var frame_durations: Array[float] = [5.0, 6.0, 7.0, 4.0]

# Set this to true (e.g. via water()) once the player waters the tile.
# While false, the sprite stays on frame 0 no matter how much time passes.
@export var water_particles: bool = false

signal stage_changed(new_frame: int)
signal fully_grown()

var _timer: float = 0.0
var _done: bool = false

func _ready() -> void:
	animation = "default"
	frame = 0
	_timer = 0.0
	_done = false

func _process(delta: float) -> void:
	if _done:
		return

	if frame == 0:
		if not water_particles:
			return  # stuck on the dry/seed frame until watered
		_advance_frame()
		return

	_timer += delta
	var idx := frame - 1
	var duration: float = frame_durations[idx] if idx < frame_durations.size() else 5.0

	if _timer >= duration:
		_timer = 0.0
		_advance_frame()

func _advance_frame() -> void:
	var max_frame := sprite_frames.get_frame_count("default") - 1
	if frame < max_frame:
		frame += 1
		stage_changed.emit(frame)
		if frame == max_frame:
			_done = true
			fully_grown.emit()
	else:
		_done = true
		fully_grown.emit()

# Call this from farm_controller.gd when the player waters the tile.
func water() -> void:
	water_particles = true
