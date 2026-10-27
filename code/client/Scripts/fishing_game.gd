extends Control
# Fishing mini game. Opened by chara_player.gd when you press F next to a lake.
# Keep the target (arrow keys) on the fish:
#   every 0.5 s you stay on it  -> bar jumps up one step
#   off the fish                -> bar slowly drains
#   bar full                    -> "Caught a Koi!" message, fish goes to the bag
#   2 minutes pass              -> "Time's up!" and the game closes by itself
# Esc = give up.

signal finished(caught: bool, fish_code: String)

# one random fish per game (same names as the animations in fish.tscn)
const FISH_TYPES := ["bluegill", "carp", "catfish", "koi", "largemouth_bass",
	"pufferfish", "rainbow_trout", "salmon", "seahorse", "sunfish"]
const MINIGAME_LAYER := 1 << 9   # physics layer 10: target only "sees" the fish, not the world

const TIME_LIMIT := 120.0     # 2 minutes, then the game closes by itself
const HOLD_TIME := 0.5        # seconds on the fish = one catch
const CATCH_STEP := 20.0      # bar goes up this much per catch (5 catches = full)
const DRAIN_PER_SEC := 8.0    # bar goes down this much per second while off the fish
const POPUP_TIME := 2.0       # how long the game lingers after "Caught a ...!"

@onready var catch_bar: ProgressBar = %CatchBar
@onready var panel: Control = $PanelContainer
@onready var aqua: Control = $PanelContainer/MarginContainer/VBoxContainer/AquaContainer
@onready var fish = get_parent().get_node("Fish")      # untyped: we set fish.gd variables on it
@onready var target = get_parent().get_node("Target")  # untyped: we use target.gd signals

var onCatch := false
var catchingValue := 0.0      # the real progress (0-100)
var fish_code := ""
var _hold := 0.0              # how long the target has been on the fish right now
var _time_left := TIME_LIMIT
var _timer_label: Label
var _ended := false


func _ready() -> void:
	fish_code = FISH_TYPES.pick_random()
	fish.aquaContainer = aqua
	fish.species = fish_code
	fish.collision_layer = MINIGAME_LAYER
	fish.collision_mask = 0
	target.collision_layer = 0
	target.collision_mask = MINIGAME_LAYER
	target.bounds = aqua
	if not target.target_entered.is_connected(_on_target_target_entered):
		target.target_entered.connect(_on_target_target_entered)
	if not target.target_exited.is_connected(_on_target_target_exited):
		target.target_exited.connect(_on_target_target_exited)

	_timer_label = _make_label(WoodPanel.SIZE_PANEL_TITLE)
	add_child(_timer_label)

	# The mini game brings its own looping track, so the map music steps aside
	# for as long as the game is open.
	AudioManager.pause_music()
	AudioManager.start_loop("minigame_music")

	# wait one frame so the containers have their final size
	await get_tree().process_frame
	# put the game box in the middle of the screen, timer right under it
	var screen := get_viewport_rect().size
	panel.global_position = (screen - panel.size) / 2.0
	_timer_label.size = Vector2(panel.size.x, 40)
	_timer_label.global_position = panel.global_position + Vector2(0, panel.size.y + 8)
	_update_timer_text()
	# fish + target start in the middle of the water
	var center := aqua.get_global_rect().get_center()
	fish.global_position = center
	target.global_position = center
	fish._set_new_target_position()


func _physics_process(delta: float) -> void:
	if _ended:
		return
	if Input.is_action_just_pressed("ui_cancel"):
		_close(false)
		return

	_time_left -= delta
	_update_timer_text()
	if _time_left <= 0.0:
		_end_with_popup(false, "Time's up!")
		return

	if onCatch:
		_hold += delta
		if _hold >= HOLD_TIME:          # stayed on the fish for 0.5 s -> one catch
			_hold -= HOLD_TIME
			catchingValue += CATCH_STEP
	else:
		_hold = 0.0                     # slipped off: the 0.5 s starts again
		catchingValue -= DRAIN_PER_SEC * delta

	catchingValue = clampf(catchingValue, 0.0, 100.0)
	# slide the bar towards the real value, so it visibly moves up and down
	catch_bar.value = lerpf(catch_bar.value, catchingValue, 12.0 * delta)
	if catchingValue >= 100.0:
		catch_bar.value = 100.0
		_end_with_popup(true, "Caught a %s!" % fish_code.replace("_", " ").capitalize())


func _update_timer_text() -> void:
	var t := int(ceil(maxf(_time_left, 0.0)))
	_timer_label.text = "%d:%02d" % [t / 60, t % 60]


# stop the game, put the result on the message line, then close
func _end_with_popup(caught: bool, message: String) -> void:
	_ended = true
	AudioManager.stop_loop("minigame_music")
	AudioManager.play("minigame_success" if caught else "minigame_failure")
	fish.set_physics_process(false)
	target.set_physics_process(false)
	# The result goes on the game's message line; the sound above is the cue.
	HousePrompt.flash(message, POPUP_TIME + 1.5, false)
	await get_tree().create_timer(POPUP_TIME).timeout
	_close(caught)


func _close(caught: bool) -> void:
	# Esc gives up part way through: no popup ran, so the failure sound is
	# played here instead.
	if AudioManager.is_looping("minigame_music"):
		AudioManager.stop_loop("minigame_music")
		AudioManager.play("minigame_failure")
	AudioManager.resume_music()
	_ended = true
	get_tree().paused = false
	finished.emit(caught, fish_code)
	get_parent().queue_free()   # removes the whole Fishing layer (box, fish, target)


func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", WoodPanel.PIXEL_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	return label


func _on_target_target_entered() -> void:
	onCatch = true

func _on_target_target_exited() -> void:
	onCatch = false
