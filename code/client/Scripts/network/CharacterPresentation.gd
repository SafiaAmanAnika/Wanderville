extends RefCounted
class_name CharacterPresentation
## Animation helper shared by local and remote characters.
## Characters use either the eight-direction front/right/back vocabulary or
## the older compass-direction player1 vocabulary. Never modify network state.

# Facing numbers from MovementProtocol.facing_from_direction():
# right, front_right, front, front_left, left, back_left, back, back_right.
# IMPORTANT: screen Y points DOWN in Godot, so front-left is (-1, +1),
# back-left is (-1, -1), and back-right is (+1, -1).
static var DIRECTIONS := [
	Vector2.RIGHT,
	Vector2(1, 1).normalized(),
	Vector2.DOWN,
	Vector2(-1, 1).normalized(),
	Vector2.LEFT,
	Vector2(-1, -1).normalized(),
	Vector2.UP,
	Vector2(1, -1).normalized(),
]

const DIRECTION_NAMES := [
	"right", "front_right", "front", "front_left",
	"left", "back_left", "back", "back_right",
]


static func sprite_of(body: Node) -> AnimatedSprite2D:
	for child in body.get_children():
		if child is AnimatedSprite2D:
			return child
	return null


static func direction_for_facing(facing: int) -> Vector2:
	return DIRECTIONS[clampi(facing, 0, 7)]


static func play(body: Node, moving: bool, direction: Vector2, facing: int) -> void:
	if body == null or not is_instance_valid(body):
		return
	if body.has_method("present_movement"):
		body.present_movement(moving, direction, facing)
		return
	var sprite := sprite_of(body)
	if sprite == null or sprite.sprite_frames == null:
		return
	if body.has_method("_play_if_new"):
		var name := "idle_front"
		if moving and direction != Vector2.ZERO:
			name = "run_" + str(body._dir_from_vector(direction))
		else:
			name = "idle_" + str(body._dir_from_vector(direction_for_facing(facing)))
		if not sprite.sprite_frames.has_animation(name):
			name = "idle_front" if not moving else "run_front"
			if not sprite.sprite_frames.has_animation(name):
				return
		body._play_if_new(name)
		return
	if body.has_method("_update_animation"):
		body._update_animation(direction if moving else Vector2.ZERO)
		return
	var frames := sprite.sprite_frames
	if moving and direction != Vector2.ZERO:
		for candidate in ["run_east", "run_south", "run_front"]:
			if frames.has_animation(candidate):
				if sprite.animation != candidate:
					sprite.play(candidate)
				return


static func prepare_gameplay(body: Node) -> void:
	var sprite := sprite_of(body)
	if sprite == null or sprite.sprite_frames == null:
		return
	sprite.speed_scale = 1.0
	sprite.sprite_frames = sprite.sprite_frames.duplicate()
	for animation in sprite.sprite_frames.get_animation_names():
		if animation.begins_with("run_"):
			sprite.sprite_frames.set_animation_speed(animation, 10.0)
		elif animation.begins_with("idle_"):
			sprite.sprite_frames.set_animation_speed(animation, 6.0)
