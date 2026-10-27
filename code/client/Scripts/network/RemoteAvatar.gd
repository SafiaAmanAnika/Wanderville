extends Node2D
class_name RemoteAvatar
## One other player's character, driven by authoritative server snapshots.
##
## Reuses the real character scene and the real animation helper, so a remote
## player looks exactly like the local one. What it deliberately does not do is
## anything the local player can:
##
## * ``process_mode`` is disabled, so its own ``_physics_process`` -- the one that
##   reads the keyboard -- never runs.
## * collision is switched off entirely, so a remote player cannot block a door or
##   push the local player.
## * cameras and audio are silenced, so following another player never steals the
##   view.
## * it is removed from the "player" group, so no gameplay system picks it up as
##   the local player and no farming or interaction code can trigger on it.
##
## Position is presentation only. It is interpolated towards the last authoritative
## position the server published; nothing here can influence the server.

## The smooth interpolation the existing remote_players.gd uses, preserved so
## remote movement feels the same as it does in the live game.
const SMOOTHING := 12.0

## Beyond this distance the entity is teleported rather than eased. A large jump
## means an authorised transition such as a respawn, where easing would visibly
## sweep the avatar across the map.
const SNAP_DISTANCE := 1500.0

var player_id := 0
var username := ""

var _body: CharacterBody2D
var _target := Vector2.ZERO
var _facing := 2
var _moving := false
var _label: Label
var _spawned_at := 0.0


func setup(player_id_: int, username_: String, character_code: String, position: Vector2,
		label_font: Font = null) -> void:
	player_id = player_id_
	username = username_
	var code := character_code if character_code != "" else "farmer_female"
	if not Global.CHARACTER_SCENES.has(code):
		code = "farmer_female"
	_body = Global.get_character_scene(code).instantiate() as CharacterBody2D
	_body.name = "Remote_%d" % player_id
	_body.use_saved_appearance = false # Appearance is local-only until it is replicated explicitly.
	add_child(_body)

	# The character's own _physics_process must never run: it reads the keyboard.
	# set_physics_process(false) rather than PROCESS_MODE_DISABLED, because the
	# latter also removes the node from processing in ways that differ from
	# simply switching off its controller.
	_body.set_physics_process(false)
	_body.remove_from_group("player")
	_body.collision_layer = 0
	_body.collision_mask = 0
	_body.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_body.velocity = Vector2.ZERO
	_body.global_position = position
	_sprite_of(_body).process_mode = Node.PROCESS_MODE_ALWAYS

	for camera in _body.find_children("*", "Camera2D", true, false):
		camera.enabled = false
	for audio in _body.find_children("*", "AudioStreamPlayer2D", true, false):
		audio.autoplay = false

	_label = Label.new()
	_label.name = "Username"
	_label.text = username
	if label_font != null:
		_label.add_theme_font_override("font", label_font)
	_label.add_theme_font_size_override("font_size", 20)
	_label.scale = Vector2.ONE / maxf(_body.scale.x, 0.001) if _body.scale.x != 0.0 else Vector2.ONE
	_label.position = Vector2(-20, -140)
	_body.add_child(_label)

	_target = position
	_spawned_at = Time.get_ticks_msec() / 1000.0


## The character's own AnimatedSprite2D, whichever of the two families this
## character belongs to. player1.tscn names it "girl"; the chara scenes name it
## "AnimatedSprite2D".
static func _sprite_of(body: Node) -> Node:
	for child in body.get_children():
		if child is AnimatedSprite2D:
			return child
	return body


func apply_snapshot(state: Dictionary) -> void:
	_target = Vector2(float(state["x"]), float(state["y"]))
	_facing = int(state.get("facing", _facing))
	_moving = bool(state.get("moving", false))


func _process(delta: float) -> void:
	if _body == null or not is_instance_valid(_body):
		return
	var offset := _target - _body.global_position
	if offset.length() > SNAP_DISTANCE:
		# Authorised jump: accept it immediately rather than easing across the map.
		_body.global_position = _target
	else:
		_body.global_position = _body.global_position.lerp(
			_target, 1.0 - exp(-SMOOTHING * delta)
		)
	_animate(offset.normalized() if offset.length() > 2.0 else Vector2.ZERO)


func _animate(direction: Vector2) -> void:
	CharacterPresentation.play(_body, _moving, direction, _facing)


func username_label() -> Label:
	return _label


func age_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0 - _spawned_at

func apply_gameplay_scale(character_code: String) -> void:
	_body.scale = Vector2.ONE * (20.0 if character_code in ["", "player1", "farmer_female"] else preload("res://Scripts/chara_frames.gd").GAMEPLAY_SCALE.x)
	_label.scale = Vector2.ONE / _body.scale
	_label.position = Vector2(-30, -140) / _body.scale
	CharacterPresentation.prepare_gameplay(_body)
