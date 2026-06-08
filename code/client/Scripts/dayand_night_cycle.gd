extends CanvasModulate
class_name DayAndNightCycle 

signal changeDayTime(dayTime: DAY_STATE)

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var weather_manager = $"../WeatherManager"

var previous_animation_pos := 0.0

enum DAY_STATE{NOON, EVENING}

var dayTime : DAY_STATE = DAY_STATE.NOON

func _ready() -> void: 
	add_to_group("DayAndNightCycle")

func _process(_delta : float) -> void:
	var animationPos = animation_player.current_animation_position
	var animationLength = animation_player.current_animation_length * 3 / 4
	
	if animationPos > animationLength && dayTime != DAY_STATE.EVENING:
		dayTime = DAY_STATE.EVENING
		changeDayTime.emit(dayTime)
	elif animationPos < animationLength && dayTime != DAY_STATE.NOON:
		dayTime = DAY_STATE.NOON
		changeDayTime.emit(dayTime)
	
	if animationPos < previous_animation_pos:
		weather_manager.on_new_day()

	previous_animation_pos = animationPos
