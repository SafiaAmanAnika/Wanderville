class_name PetSound
extends Node
## Gives a pet its voice. Add it as a child of the pet, set `sound`, and it
## calls out now and then while it is idle, plus once on every click.
##
##   var voice := PetSound.new()
##   voice.sound = "meow"   # or "woof"
##   add_child(voice)

@export var sound := "meow"
@export var min_gap := 9.0    ## shortest wait between idle calls, in seconds
@export var max_gap := 20.0   ## longest wait
@export var click_radius := 60.0

var _countdown := 0.0
var _owner2d: Node2D


func _ready() -> void:
	_owner2d = get_parent() as Node2D
	_reset()


func _process(delta: float) -> void:
	_countdown -= delta
	if _countdown <= 0.0:
		speak()
		_reset()


## The pet answers when you click on it.
func _input(event: InputEvent) -> void:
	if _owner2d == null:
		return
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	var world := _owner2d.get_global_mouse_position()
	if world.distance_to(_owner2d.global_position) <= click_radius:
		speak()
		_reset()


func speak() -> void:
	AudioManager.play(sound, 0.06)


func _reset() -> void:
	_countdown = randf_range(min_gap, max_gap)
