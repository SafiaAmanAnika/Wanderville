extends Node2D

enum Season {
	SUMMER,
	AUTUMN,
	WINTER,
	SPRING
}

var current_season : Season = Season.SUMMER

@onready var season_timer = $SeasonTimer
@onready var weather_timer = $WeatherTimer

@onready var rain = $"../WeatherFXManager/Rain"
@onready var snow = $"../WeatherFXManager/Snow"
@onready var wind = $"../WeatherFXManager/Wind"
@onready var autumn_leaves = $"../WeatherFXManager/Autumn_leaves"
@onready var spring_leaves = $"../WeatherFXManager/Spring_leaves"


func _ready():
	season_timer.timeout.connect(_on_season_timer_timeout)
	weather_timer.timeout.connect(_on_weather_timer_timeout)

	update_season_effects()


func _on_season_timer_timeout():
	current_season = ((current_season + 1) % 4) as Season
	update_season_effects()


func _on_weather_timer_timeout():

	if current_season == Season.SUMMER:

		rain.emitting = true

		await get_tree().create_timer(5.0).timeout

		if current_season == Season.SUMMER:
			rain.emitting = false

		weather_timer.start()


func update_season_effects():

	rain.emitting = false
	snow.emitting = false
	wind.emitting = false
	autumn_leaves.emitting = false
	spring_leaves.emitting = false

	weather_timer.stop()

	match current_season:

		Season.SUMMER:
			weather_timer.start()

		Season.AUTUMN:
			autumn_leaves.emitting = true

		Season.WINTER:
			snow.emitting = true

		Season.SPRING:
			spring_leaves.emitting = true
			wind.emitting = true


func get_season_name() -> String:
	match current_season:
		Season.SUMMER:
			return "Summer"
		Season.AUTUMN:
			return "Autumn"
		Season.WINTER:
			return "Winter"
		Season.SPRING:
			return "Spring"

	return ""


func _process(_delta):
	var cam = get_viewport().get_camera_2d()
	if cam:
		global_position = cam.global_position
