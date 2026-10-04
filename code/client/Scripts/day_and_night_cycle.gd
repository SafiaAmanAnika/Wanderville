extends CanvasModulate
class_name DayAndNightCycle

signal changeDayTime(dayTime: DAY_STATE)

@onready var animation_player: AnimationPlayer = get_node_or_null("AnimationPlayer")
@onready var weather_manager = get_node_or_null("../Map/WeatherManager")

enum DAY_STATE { NOON, EVENING }
var dayTime: DAY_STATE = DAY_STATE.NOON

const DAY_LENGTH: float = 1800.0
const NIGHT_LENGTH: float = 600.0
const CYCLE_LENGTH: float = DAY_LENGTH + NIGHT_LENGTH  # 2400.0 = 40 minutes

var time_elapsed: float = 0.0

func _ready() -> void:
	add_to_group("DayAndNightCycle")
	
	if animation_player and animation_player.has_animation(animation_player.current_animation):
		animation_player.pause()



func _update_day_state() -> void:
	var is_night := time_elapsed >= DAY_LENGTH

	if is_night && dayTime != DAY_STATE.EVENING:
		dayTime = DAY_STATE.EVENING
		changeDayTime.emit(dayTime)
	elif !is_night && dayTime != DAY_STATE.NOON:
		dayTime = DAY_STATE.NOON
		changeDayTime.emit(dayTime)

func _update_animation() -> void:
	if not animation_player or animation_player.current_animation.is_empty():
		var phase := time_elapsed / CYCLE_LENGTH
		var night := Color(0.34, 0.40, 0.62)
		if phase < 0.65:
			color = Color.WHITE
		elif phase < 0.75:
			color = Color.WHITE.lerp(night, (phase - 0.65) / 0.10)
		elif phase < 0.95:
			color = night
		else:
			color = night.lerp(Color.WHITE, (phase - 0.95) / 0.05)
		return
	var anim_length := animation_player.current_animation_length
	if anim_length <= 0.0:
		return
	var progress := time_elapsed / CYCLE_LENGTH
	animation_player.seek(progress * anim_length, true)

func _process(delta: float) -> void:
	if Global.is_logged_in() and not GameState.world_state.is_empty():
		time_elapsed = GameState.world_time_fraction() * CYCLE_LENGTH
		_update_day_state()
		_update_animation()
		return
	time_elapsed += delta

	if time_elapsed >= CYCLE_LENGTH:
		time_elapsed -= CYCLE_LENGTH
		if weather_manager:
			weather_manager.on_new_day()

	_update_day_state()
	_update_animation()
