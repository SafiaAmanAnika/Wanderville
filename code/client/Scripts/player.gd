extends CharacterBody2D

# --- Settings ---
const SPEED = 300.0

# --- Node references ---
@onready var anim = $girl

func _physics_process(delta):
	# Get input
	var input = Vector2.ZERO
	input.x = Input.get_axis("ui_left", "ui_right")
	input.y = Input.get_axis("ui_up", "ui_down")
	
	# Normalize so diagonal isn't faster
	if input.length() > 1.0:
		input = input.normalized()
	
	# Move
	velocity = input * SPEED
	move_and_slide()
	
	# Animate
	_update_animation(input)

func _update_animation(input: Vector2):
	if input == Vector2.ZERO:
		# Player is standing still — stop animation
		anim.stop()
		return
	
	# Play animation based on direction
	anim.play(_get_direction_animation(input))

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
