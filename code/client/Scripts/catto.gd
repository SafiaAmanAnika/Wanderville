extends CharacterBody2D

# --- Settings ---
const FOLLOW_SPEED = 200.0
const FOLLOW_DISTANCE = 250.0
const IDLE_TIME_TO_LICK = 2.0
const IDLE_TIME_TO_SLEEP = 5.0

@onready var player: CharacterBody2D = $"../girl"
@onready var anim: AnimatedSprite2D = $Catto

var idle_timer: float = 0.0

func _ready():
	if player == null:
		print("Could not find girl node!")
	else:
		global_position = player.global_position + Vector2(50, 0)

func _physics_process(delta: float) -> void:
	if player == null:
		return

	var distance = global_position.distance_to(player.global_position)

	if distance > FOLLOW_DISTANCE:
		idle_timer = 0.0
		var direction = (player.global_position - global_position).normalized()
		velocity = direction * FOLLOW_SPEED
		move_and_slide()
		_play_walk_animation(direction)
	else:
		velocity = Vector2.ZERO
		move_and_slide()
		idle_timer += delta
		if idle_timer >= IDLE_TIME_TO_SLEEP:
			anim.play("cat slep")
		elif idle_timer >= IDLE_TIME_TO_LICK:
			anim.play("cat lick")
		else:
			anim.play("cat sit")

func _play_walk_animation(direction: Vector2):
	if direction.y < 0 and abs(direction.y) >= abs(direction.x):
		anim.play("walk up")
	elif direction.y > 0 and abs(direction.y) >= abs(direction.x):
		anim.play("walk down")
	elif direction.x > 0:
		anim.play("walk right")
	else:
		anim.play("walk left")
