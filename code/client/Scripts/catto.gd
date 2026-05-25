extends AnimatedSprite2D

# --- Settings ---
const FOLLOW_SPEED = 200.0
const FOLLOW_DISTANCE = 250.0
const IDLE_TIME_TO_LICK = 2.0
const IDLE_TIME_TO_SLEEP = 5.0

# --- Drag your player node here in the Inspector ---
@export var player: Node2D

var idle_timer: float = 0.0

func _ready():
	if player == null:
		print("Please assign the player node in the Inspector!")
	else:
		global_position = player.global_position + Vector2(50, 0)

func _process(delta: float) -> void:
	if player == null:
		return

	var distance = global_position.distance_to(player.global_position)

	if distance > FOLLOW_DISTANCE:
		idle_timer = 0.0
		var direction = (player.global_position - global_position).normalized()
		position += direction * FOLLOW_SPEED * delta
		_play_walk_animation(direction)
	else:
		idle_timer += delta
		if idle_timer >= IDLE_TIME_TO_SLEEP:
			play("cat slep")
		elif idle_timer >= IDLE_TIME_TO_LICK:
			play("cat lick")
		else:
			play("cat sit")

func _play_walk_animation(direction: Vector2):
	if direction.y < 0 and abs(direction.y) >= abs(direction.x):
		play("walk up")
	elif direction.y > 0 and abs(direction.y) >= abs(direction.x):
		play("walk down")
	elif direction.x > 0:
		play("walk right")
	else:
		play("walk left")
