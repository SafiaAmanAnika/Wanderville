extends CharacterBody2D

@export var aquaContainer : Control

@onready var fish_sprite: AnimatedSprite2D = $AnimatedSprite2D

const MIN_SPEED := 80.0     # each swim picks a random speed between these
const MAX_SPEED := 170.0
const MIN_REST := 0.2       # and rests a random time when it arrives
const MAX_REST := 1.0

var speed := 100.0

var targetPosition: Vector2
var borderDistance := 24   # keep the whole fish inside the water box
var species := ""   # which fish animation to play (set by fishing_game.gd)

func _ready() -> void:
	_set_target_position()
	
func _set_target_position() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	_set_new_target_position()
	
func _set_new_target_position() -> void:
	if aquaContainer == null:
		return
	var boxSize := aquaContainer.get_global_rect()
	var xPosition := randi_range(
		boxSize.position.x + borderDistance, boxSize.position.x + boxSize.size.x - borderDistance)
	var yPosition := randi_range(
		boxSize.position.y + borderDistance, boxSize.position.y + boxSize.size.y - borderDistance)
	
	targetPosition = Vector2(xPosition, yPosition)
	speed = randf_range(MIN_SPEED, MAX_SPEED)

func _physics_process(delta: float) -> void:
	var direction := (targetPosition - global_position).normalized()

	if direction:
		velocity = direction * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.y = move_toward(velocity.y, 0, speed)
		
	if global_position.distance_to(targetPosition) < 5: _on_target()
		
	_set_animation()

	move_and_slide()

func _on_target() -> void:
	set_physics_process(false)
	await get_tree().create_timer(randf_range(MIN_REST, MAX_REST)).timeout
	
	_set_new_target_position()
	
	set_physics_process(true)
	
func _set_animation() -> void:
	if velocity.x != 0:
		fish_sprite.flip_h = velocity.x < 0   # face the way it swims
	if velocity:
		fish_sprite.play(species if species != "" else fish_sprite.animation)
	else: fish_sprite.stop()
