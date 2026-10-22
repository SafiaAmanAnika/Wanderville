extends Node2D
# One door. Near it: "Press H to open the door" / "Press H to close the door".
# Closed: the Blocker fills the doorway, so the player can't pass.
# Open:   the Blocker is switched off, so the player can walk through.

# Some door animations are drawn closed→open, others open→closed.
# Tick this when the LAST frame is the closed door.
@export var closed_is_last_frame := false

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var blocker: CollisionShape2D = $Blocker/CollisionShape2D

var is_open := false
var _player_near := false


func _ready() -> void:
	# the door animation should play once, not loop forever
	anim.sprite_frames.set_animation_loop(anim.animation, false)
	anim.stop()
	anim.frame = _closed_frame()         # show the closed door
	blocker.disabled = false             # starts closed
	$Reach.body_entered.connect(_on_body_entered)
	$Reach.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_near = true
		_update_prompt()


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_near = false
		HousePrompt.hide_text()


func _unhandled_input(event: InputEvent) -> void:
	if _player_near and event.is_action_pressed("door"):
		get_viewport().set_input_as_handled()   # only this door reacts
		toggle()


func toggle() -> void:
	is_open = not is_open
	# play towards the open frame, or back towards the closed frame
	var forwards := is_open != closed_is_last_frame
	if forwards:
		anim.play(anim.animation)
	else:
		anim.play_backwards(anim.animation)
	blocker.set_deferred("disabled", is_open)
	_update_prompt()


func _update_prompt() -> void:
	HousePrompt.show_text("Press H to close the door" if is_open else "Press H to open the door")



func _closed_frame() -> int:
	return anim.sprite_frames.get_frame_count(anim.animation) - 1 if closed_is_last_frame else 0
