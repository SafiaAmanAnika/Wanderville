extends Node2D

const WeatherManager = preload("../Scripts/weather_manager.gd")

@onready var weather_manager = $"../WeatherManager"
@onready var rain: GPUParticles2D = $Rain
@onready var snow: GPUParticles2D = $Snow

func _ready():
	weather_manager.season_changed.connect(_on_season_changed)
	_on_season_changed(weather_manager.current_season)

func _on_season_changed(season: int) -> void:
	rain.emitting = false
	snow.emitting = false

	match season:
		WeatherManager.Season.SUMMER:
			pass

		WeatherManager.Season.WINTER:
			snow.emitting = true

		WeatherManager.Season.AUTUMN:
			rain.emitting = true

		WeatherManager.Season.SPRING:
			rain.emitting = true
