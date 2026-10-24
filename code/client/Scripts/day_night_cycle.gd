extends CanvasModulate

# Duration settings (real-world seconds)
@export var daytime_duration: float = 1500.0  # 25 minutes, 1500
@export var nighttime_duration: float = 300.0  # 5 minutes, 300
@export var transition_duration: float = 60.0  # 1 minute per transition, 60

# In-game clock settings
@export_range(0, 23) var starting_hour: int = 6

# Lighting colors
@export var day_color: Color = Color(1,1,1)
@export var night_color: Color = Color(0.229, 0.23, 0.408, 1.0)

var time_in_hours: float = 6.0
var elapsed_time: float = 0.0

const HOURS_PER_DAY := 24.0

func _ready() -> void:
	time_in_hours = float(starting_hour)
	elapsed_time = time_in_hours / HOURS_PER_DAY * (daytime_duration + nighttime_duration)
	
	# Start with the correct lighting.
	update_lighting()

func _process(delta: float) -> void:
	var total_duration := daytime_duration + nighttime_duration
	elapsed_time = fmod(elapsed_time + delta,total_duration)

	# Convert elapsed real time into in-game hours.
	time_in_hours = elapsed_time / total_duration * HOURS_PER_DAY

	update_lighting()


func update_lighting() -> void:
	var _total_duration := daytime_duration + nighttime_duration
	var day_progress := elapsed_time

	var blend_factor: float

	if day_progress < daytime_duration:
		# Daytime: transition smoothly into night near sunset.
		var sunset_start := daytime_duration - transition_duration
		
		if day_progress < sunset_start:
			blend_factor = 1.0
		else:
			var progress := (day_progress - sunset_start) / transition_duration
			blend_factor = 1.0 - smoothstep(0.0, 1.0, progress)
	else:
		# Nighttime: transition smoothly back to daylight.
		var night_progress := day_progress - daytime_duration
		var sunrise_start := nighttime_duration - transition_duration

		if night_progress < sunrise_start:
			blend_factor = 0.0
		else:
			var progress := (night_progress - sunrise_start) / transition_duration
			blend_factor = smoothstep(0.0, 1.0, progress)
	
	color = night_color.lerp(day_color, blend_factor)


func get_current_hour() -> int:
	return int(time_in_hours) % 24

func get_current_minute() -> int:
	return int((time_in_hours - floor(time_in_hours)) * 60.0)

func is_daytime() -> bool:
	return elapsed_time < daytime_duration

func is_nighttime() -> bool:
	return not is_daytime()
