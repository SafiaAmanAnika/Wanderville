extends Node2D

enum Season {
	SUMMER,
	AUTUMN,
	WINTER,
	SPRING
}

var current_season = Season.SUMMER

@onready var rain = $"../Rain"
@onready var weather_timer = $WeatherTimer

func _ready():
	rain.emitting = false
	
	# DEBUG
	print("WeatherManager ready!")
	print("Rain node found: ", rain != null)
	print("Rain path: ", rain.get_path())
	print("WeatherTimer found: ", weather_timer != null)
	print("Current season: ", current_season)
	
	weather_timer.timeout.connect(_on_weather_timer_timeout)
	start_random_weather_timer()
	
func start_random_weather_timer():
	weather_timer.wait_time = randf_range(60.0, 180.0)
	weather_timer.start()

func _on_weather_timer_timeout():
	if current_season == Season.SUMMER:
		
		if randf() < 0.2:
			start_rain()
		
	start_random_weather_timer()

func start_rain():
	rain.emitting = true
	
	await get_tree().create_timer(randf_range(20.0, 60.0)).timeout
	
	rain.emitting = false
