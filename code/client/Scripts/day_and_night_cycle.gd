extends CanvasModulate
class_name DayAndNightCycle

signal changeDayTime(dayTime: DAY_STATE)

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var weather_manager = $"../WeatherManager"

enum DAY_STATE { NOON, EVENING }
var dayTime: DAY_STATE = DAY_STATE.NOON

const DAY_LENGTH: float = 30.0   # 30 minutes in seconds
const NIGHT_LENGTH: float = 10.0  # 10 minutes in seconds
const CYCLE_LENGTH: float = DAY_LENGTH + NIGHT_LENGTH  # 2400.0 = 40 minutes

var time_elapsed: float = 0.0

func _ready() -> void:
	add_to_group("DayAndNightCycle")
	
	if animation_player.has_animation(animation_player.current_animation):
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
	var anim_length := animation_player.current_animation_length
	if anim_length <= 0.0:
		return
	var progress := time_elapsed / CYCLE_LENGTH
	animation_player.seek(progress * anim_length, true)

func _process(delta: float) -> void:
	time_elapsed += delta

	if time_elapsed >= CYCLE_LENGTH:
		time_elapsed -= CYCLE_LENGTH
		weather_manager.on_new_day()

	var was_day := dayTime == DAY_STATE.NOON
	_update_day_state()
	if was_day && dayTime == DAY_STATE.EVENING:
		print("NIGHT STARTED at time_elapsed=", time_elapsed)

	var anim_length := animation_player.current_animation_length
	if anim_length > 0.0:
		var progress := time_elapsed / CYCLE_LENGTH
		animation_player.seek(progress * anim_length, true)
