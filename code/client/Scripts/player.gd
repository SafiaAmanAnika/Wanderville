extends CharacterBody2D

# --- Settings ---
const SPEED = 300.0
@export var require_world_connection := true
@export var use_saved_appearance := true

# --- Node references ---
@onready var anim = $girl

var _facing := "south"   # last direction moved, used for the idle pose


func _ready() -> void:
	# Above the map's y-sorted ground tiles, like chara_player.gd; at the map's
	# level a ground tile hid the character in the upper half of every tile.
	z_index = 2
	if use_saved_appearance:
		preload("res://Scripts/ui/player_namecard.gd").attach(self, "", true)


func _physics_process(delta):
	# FREEZE WHEN MENU IS OPEN
	if GameState.menu_open or GameState.social_open or get_viewport().gui_get_focus_owner() is LineEdit:
		velocity = Vector2.ZERO
		_stand_still()
		return

	# Get input
	var input = Vector2(
		Input.get_axis("ui_left", "ui_right"),
		Input.get_axis("ui_up", "ui_down")
	)
	
	# ALWAYS normalize to prevent diagonal speed boost
	if input != Vector2.ZERO:
		input = input.normalized()
	
	# Move
	velocity = input * SPEED
	move_and_slide()
	
	# Animate
	_update_animation(input)

func _update_animation(input: Vector2):
	if input == Vector2.ZERO:
		_stand_still()
		return
	
	AudioManager.start_loop("walk", -6.0)
	# Play animation based on direction
	var run_anim := _get_direction_animation(input)
	_facing = run_anim.trim_prefix("run_")
	if anim.animation != run_anim:
		var keep_phase: bool = String(anim.animation).begins_with("run_")
		var phase: float = (anim.frame + anim.frame_progress) / anim.sprite_frames.get_frame_count(anim.animation)
		anim.play(run_anim)
		if keep_phase:
			var next: float = phase * anim.sprite_frames.get_frame_count(run_anim)
			anim.set_frame_and_progress(int(next), fposmod(next, 1.0))
	elif not anim.is_playing():
		anim.play(run_anim)


# New characters have idle animations; the old girl doesn't, so she just stops
func _stand_still() -> void:
	AudioManager.stop_loop("walk")
	var idle := "idle_" + _facing
	if anim.sprite_frames.has_animation(idle):
		if anim.animation != idle:
			anim.play(idle)
	else:
		anim.stop()

func _get_direction_animation(input: Vector2) -> String:
	var angle = input.angle()
	var degrees = rad_to_deg(angle)
	
	# Normalize to 0-360
	if degrees < 0:
		degrees += 360
	
	# Map angle to 8 directions
	# Each direction covers a 45 degree slice
	if degrees < 22.5 or degrees >= 337.5:
		return "run_east"
	elif degrees < 67.5:
		return "run_south_east"
	elif degrees < 112.5:
		return "run_south"
	elif degrees < 157.5:
		return "run_south_west"
	elif degrees < 202.5:
		return "run_west"
	elif degrees < 247.5:
		return "run_north_west"
	elif degrees < 292.5:
		return "run_north"
	else:
		return "run_north_east"


func _exit_tree() -> void:
	AudioManager.stop_loop("walk")
