extends Node2D

const WeatherManager = preload("../Scripts/weather_manager.gd")

@onready var weather_manager = $"../WeatherManager"
@onready var rain: GPUParticles2D = $Rain
@onready var snow: GPUParticles2D = $Snow
@onready var autumn_leaves: GPUParticles2D = $Autumn_leaves
@onready var spring_leaves: GPUParticles2D = $Spring_leaves

func _ready():
	weather_manager.season_changed.connect(_on_season_changed)
	_on_season_changed(weather_manager.current_season)
	GameState.world_updated.connect(_apply_world)
	_apply_world(GameState.world_state)

func _on_season_changed(season: int) -> void:
	rain.emitting = false
	snow.emitting = false
	autumn_leaves.emitting = false
	spring_leaves.emitting = false

	match season:
		WeatherManager.Season.SUMMER:
			rain.emitting = true
			
		WeatherManager.Season.AUTUMN:
			autumn_leaves.emitting = true

		WeatherManager.Season.WINTER:
			snow.emitting = true

		WeatherManager.Season.SPRING:
			spring_leaves.emitting = true

func _apply_world(state: Dictionary) -> void:
	if state.is_empty():
		return
	rain.emitting = state.get("weather", "clear") == "rain"
	snow.emitting = state.get("weather", "clear") == "snow"
