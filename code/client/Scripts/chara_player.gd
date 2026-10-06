extends CharacterBody2D
# One script for every character scene (charagirlA/B/C, charaboyA/B/C).
#   Arrow keys / WASD -> walk in 8 directions
#   Standing still    -> idle facing the last direction
#   play_action("hoe" / "water" / "fish") -> plays that animation once, then back to idle
#
# The scenes already have idle / hoe / water / fish / death animations.
# They have no run animation, so this script cuts it from run.png (same folder as the idle sheet).

const SPEED = 300.0
const CELL := 448   # every sprite sheet frame is 448x448
const COLUMNS := 6

# sheet row -> direction name used in the scenes (idle_front, water_back_left, ...)
const ROW_DIRS := ["front", "front_right", "right", "back_right", "back", "back_left", "left", "front_left"]

@export var sheet_folder := ""   # empty = found automatically from the idle animation

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

var facing := "front"
var _busy := false   # true while an action (hoe/water/fish) is playing


func _ready() -> void:
	add_to_group("player")
	z_index = 2
	anim.sprite_frames = anim.sprite_frames.duplicate()   # own copy, so adding animations doesn't touch other scenes
	if sheet_folder == "":
		sheet_folder = _find_sheet_folder()
	_add_sheet_animations("run", "run.png", 10.0, true)
	_add_sheet_animations("idle", "idle.png", 6.0, true)   # fills in the diagonal idles the scene doesn't have
	for action in ["hoe", "water", "fish", "death"]:
		for dir in ROW_DIRS:
			var a: String = "%s_%s" % [action, dir]
			if anim.sprite_frames.has_animation(a):
				anim.sprite_frames.set_animation_loop(a, false)   # actions play once
	anim.speed_scale = 1.0
	anim.play("idle_front")


func _physics_process(_delta: float) -> void:
	if _busy or GameState.menu_open or GameState.social_open \
			or get_viewport().gui_get_focus_owner() is LineEdit \
			or (Global.is_logged_in() and not APIClient.realtime.connected):
		velocity = Vector2.ZERO
		if not _busy:
			_play_if_new("idle_" + facing)
		return

	var input := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	if input != Vector2.ZERO:
		input = input.normalized()
		facing = _dir_from_vector(input)
		_play_if_new("run_" + facing)
	else:
		_play_if_new("idle_" + facing)
	velocity = input * SPEED
	move_and_slide()


# Call this from farming/fishing code, e.g. player.play_action("water")
func play_action(action: String) -> void:
	var a := _closest_animation(action)
	if a == "":
		return
	_busy = true
	anim.play(a)
	await anim.animation_finished
	_busy = false
	anim.play("idle_" + facing)


# ─── helpers ─────────────────────────────────────────────────────────

func _play_if_new(a: String) -> void:
	if anim.animation != a and anim.sprite_frames.has_animation(a):
		anim.play(a)


# 8 directions, 45 degrees each. Godot angles: 0 = right, 90 = down.
func _dir_from_vector(v: Vector2) -> String:
	var i := int(round(rad_to_deg(v.angle()) / 45.0)) % 8
	if i < 0:
		i += 8
	# angle slot -> row index: right, front_right, front, front_left, left, back_left, back, back_right
	return ["right", "front_right", "front", "front_left", "left", "back_left", "back", "back_right"][i]


# Some actions don't have every direction (e.g. no hoe_front), so fall back to a side view
func _closest_animation(action: String) -> String:
	var side := "left" if facing.ends_with("left") else "right"
	for d in [facing, side, "front", "right"]:
		if anim.sprite_frames.has_animation(action + "_" + d):
			return action + "_" + d
	return ""


func _find_sheet_folder() -> String:
	for a in anim.sprite_frames.get_animation_names():
		var tex := anim.sprite_frames.get_frame_texture(a, 0) as AtlasTexture
		if tex != null and tex.atlas != null:
			return tex.atlas.resource_path.get_base_dir()
	return ""


# Cut one sprite sheet (6 columns x 8 rows) into 8 animations: <prefix>_front, <prefix>_right, ...
# Animations the scene already has are kept as they are.
func _add_sheet_animations(prefix: String, file: String, fps: float, loop: bool) -> void:
	var path := sheet_folder + "/" + file
	if not ResourceLoader.exists(path):
		return
	var sheet: Texture2D = load(path)
	var frames := anim.sprite_frames
	for row in ROW_DIRS.size():
		var a: String = prefix + "_" + ROW_DIRS[row]
		if frames.has_animation(a):
			continue
		frames.add_animation(a)
		frames.set_animation_speed(a, fps)
		frames.set_animation_loop(a, loop)
		for col in COLUMNS:
			var tex := AtlasTexture.new()
			tex.atlas = sheet
			tex.region = Rect2(col * CELL, row * CELL, CELL, CELL)
			frames.add_frame(a, tex)
