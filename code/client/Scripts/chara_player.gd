extends CharacterBody2D
# One script for every character scene (charagirlA/B/C, charaboyA/B/C).
#   Arrow keys / WASD -> walk in 8 directions
#   Standing still    -> idle facing the last direction
#   play_action("hoe" / "water" / "fish") -> plays that animation once, then back to idle
#   F next to a lake  -> opens the fishing mini game
#
# The scenes already have idle / hoe / water / fish / death animations.
# They have no run animation, so this script cuts it from run.png (same folder as the idle sheet).

const SPEED = 300.0
const CELL := 448   # every sprite sheet frame is 448x448
const COLUMNS := 6
const CharaFrames := preload("res://Scripts/chara_frames.gd")

# sheet row -> direction name used in the scenes (idle_front, water_back_left, ...)
const ROW_DIRS := ["front", "front_right", "right", "back_right", "back", "back_left", "left", "front_left"]

@export var sheet_folder := ""   # empty = found automatically from the idle animation
@export var require_world_connection := true # Local-only rooms do not join campus presence.
@export var use_saved_appearance := true # Remote players must never inherit this client's look.

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

var facing := "front"
var _busy := false   # true while an action (hoe/water/fish) is playing

# ─── Fishing ─────────────────────────────────────────────────────────
const FISHING_SCENE := "res://Scenes/fishing.tscn"

var near_water := false      # set by WaterSource when you walk next to a lake
var fishing := false         # true while the mini game is open


func _ready() -> void:
	add_to_group("player")
	z_index = 2
	# Top-down game: "floating" = no floor/gravity rules. The default ("grounded") treats
	# slanted lake edges as floors and keeps snapping onto them -> the screen shakes.
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_simplify_collision()
	anim.sprite_frames = anim.sprite_frames.duplicate()   # own copy, so adding animations doesn't touch other scenes
	if sheet_folder == "":
		sheet_folder = _find_sheet_folder()
	_add_sheet_animations("run", "run.png", 10.0, true)
	_add_sheet_animations("walk", "run.png", 6.0, true)
	_add_sheet_animations("idle", "idle.png", 6.0, true)   # fills in the diagonal idles the scene doesn't have
	_add_sheet_animations("scythe", "scythe.png", 8.0, false)
	if not CharaFrames.longer_leg_folder(sheet_folder).is_empty():
		for action in ["hoe", "water", "fish"]:
			CharaFrames.add_sheet_animations(anim.sprite_frames, sheet_folder, action, CharaFrames.FILES[action], 8.0, false, true)
	for action in ["hoe", "water", "fish", "scythe", "axe", "death"]:
		for dir in ROW_DIRS:
			var a: String = "%s_%s" % [action, dir]
			if anim.sprite_frames.has_animation(a):
				anim.sprite_frames.set_animation_loop(a, false)   # actions play once
	anim.speed_scale = 1.0
	anim.play("idle_front")
	_add_fish_key()


func _physics_process(_delta: float) -> void:
	if fishing:
		velocity = Vector2.ZERO
		return
	if _busy or GameState.menu_open or GameState.social_open \
			or get_viewport().gui_get_focus_owner() is LineEdit:
		velocity = Vector2.ZERO
		if not _busy:
			_play_if_new("idle_" + facing)
		return

	if near_water and Input.is_action_just_pressed("fish"):
		_open_minigame()
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


# ─── Fishing ─────────────────────────────────────────────────────────

# WaterSource calls this when you walk in / out of a lake area
func set_near_water(value: bool) -> void:
	near_water = value


func _open_minigame() -> void:
	fishing = true
	anim.play("idle_" + facing)
	var layer: Node = load(FISHING_SCENE).instantiate()
	get_tree().current_scene.add_child(layer)
	get_tree().paused = true              # the world stops while you play
	PhysicsServer2D.set_active(true)      # but the mini game still needs physics (fish + target)
	var game = layer.get_node("FishingGame")   # untyped: "finished" is our own signal
	game.finished.connect(_on_minigame_finished, CONNECT_ONE_SHOT)


# the mini game already showed "Caught a Koi!"; here we only store the fish
func _on_minigame_finished(caught: bool, fish_code: String) -> void:
	fishing = false
	if caught:
		var fish_name := fish_code.replace("_", " ").capitalize()
		GameState.add_item_offline(fish_code, fish_name, 1, "fish", "fish")


# F key, added in code so project.godot doesn't need editing
func _add_fish_key() -> void:
	if InputMap.has_action("fish"):
		return
	InputMap.add_action("fish")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F
	InputMap.action_add_event("fish", key)


# The scenes' collision outline has a thin dent in it; pushing that dent against
# a lake corner makes the body bounce back and forth. Use the same area without the dent
# (the outer outline of the same points).
func _simplify_collision() -> void:
	var shape := get_node_or_null("CollisionPolygon2D") as CollisionPolygon2D
	if shape and shape.polygon.size() > 4:
		var hull := Geometry2D.convex_hull(shape.polygon)
		hull.remove_at(hull.size() - 1)   # convex_hull repeats the first point at the end
		shape.polygon = hull


# ─── helpers ─────────────────────────────────────────────────────────

func _play_if_new(a: String) -> void:
	if anim.animation != a and anim.sprite_frames.has_animation(a):
		# Keep the original stride continuous through turns and Walk/Run changes.
		var keep_phase: bool = String(anim.animation).get_slice("_", 0) in ["walk", "run"] \
				and a.get_slice("_", 0) in ["walk", "run"]
		var phase := (anim.frame + anim.frame_progress) / anim.sprite_frames.get_frame_count(anim.animation)
		anim.play(a)
		if keep_phase:
			var next := phase * anim.sprite_frames.get_frame_count(a)
			anim.set_frame_and_progress(int(next), fposmod(next, 1.0))
	elif anim.animation == a and not anim.is_playing():
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
	var replace := prefix in ["idle", "walk", "run"] or not CharaFrames.longer_leg_folder(sheet_folder).is_empty()
	CharaFrames.add_sheet_animations(anim.sprite_frames, sheet_folder, prefix, file, fps, loop, replace)


# The ENet adapter keeps the existing fishing and action input rules.
func network_input_allowed() -> bool:
	if fishing or _busy:
		return false
	if near_water and Input.is_action_just_pressed("fish"):
		_open_minigame()
		return false
	return true
