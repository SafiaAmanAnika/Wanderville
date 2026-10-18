extends RefCounted
class_name CharacterPresentation
## Animation for both character families, without inventing a third vocabulary.
##
## Wanderville has two incompatible character conventions, and both are in real
## use by existing scenes, so presentation has to speak both:
##
## * ``chara_player.gd`` (charagirlA..charaboyC) uses ``run_front`` /
##   ``idle_front`` plus eight diagonals, and cuts the run sheet out of run.png at
##   load time because the scenes ship no run animation.
## * ``player.gd`` (player1.tscn) uses compass names, ``run_east``, and has no idle
##   animation at all -- so "idle" there means stopping on the current frame.
##
## Choosing animations here rather than in each caller keeps the local player and
## a remote avatar from drifting apart as the sheet logic changes.

## Direction slots, matching the row order both sheets use:
## right, front_right, front, front_left, left, back_left, back, back_right.
## Not a const: a Vector2 constructor call is not a constant expression in GDScript.
static var DIRECTIONS := [
	Vector2.RIGHT,
	Vector2(1, 1).normalized(),
	Vector2.DOWN,
	Vector2(1, -1).normalized(),
	Vector2.LEFT,
	Vector2(-1, 1).normalized(),
	Vector2.UP,
	Vector2(-1, -1).normalized(),
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
	var sprite := sprite_of(body)
	if sprite == null:
		return
	if body.has_method("_play_if_new"):
		# chara_player.gd family. Its _dir_from_vector is reused so the row this
		# picks is exactly the row its own controller would pick.
		var name := "idle_front"
		if moving and direction != Vector2.ZERO:
			name = "run_" + str(body._dir_from_vector(direction))
		else:
			name = "idle_" + str(body._dir_from_vector(direction_for_facing(facing)))
		if not sprite.sprite_frames.has_animation(name):
			name = "idle_front" if not moving else "run_front"
			if not sprite.sprite_frames.has_animation(name):
				return
		if sprite.animation != name:
			sprite.play(name)
		return
	if body.has_method("_update_animation"):
		# player.gd family. It has run_* but no idle*, and its own method already
		# handles that by stopping the sprite.
		body._update_animation(direction if moving else Vector2.ZERO)
		return
	# Last resort: any sprite frames that happen to expose compass names.
	var frames := sprite.sprite_frames
	if moving and direction != Vector2.ZERO:
		for candidate in ["run_east", "run_south", "run_front"]:
			if frames.has_animation(candidate):
				if sprite.animation != candidate:
					sprite.play(candidate)
				return

# Approved experimental presentation, applied only to runtime instances.
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
