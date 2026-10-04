extends Node2D

const WeatherManager = preload("../Scripts/weather_manager.gd")

@onready var weather_manager = $"../WeatherManager"
@onready var rain: GPUParticles2D = $Rain
@onready var snow: GPUParticles2D = $Snow
@onready var autumn_leaves: GPUParticles2D = $Autumn_leaves
@onready var spring_leaves: GPUParticles2D = $Spring_leaves

func _ready():
	initialize()

var _initialized := false

func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	weather_manager = get_node("../WeatherManager")
	rain = get_node("Rain")
	snow = get_node("Snow")
	autumn_leaves = get_node("Autumn_leaves")
	spring_leaves = get_node("Spring_leaves")
	weather_manager.season_changed.connect(_on_season_changed)
	_on_season_changed(weather_manager.current_season)
	GameState.world_updated.connect(_apply_world)
	_apply_world(GameState.world_state)

func _on_season_changed(season: int) -> void:
	# Online precipitation comes from world_updated. Do not overwrite it when
	# the season signal arrives later in the same update.
	if not Global.is_logged_in():
		rain.emitting = false
		snow.emitting = false
	autumn_leaves.emitting = false
	spring_leaves.emitting = false

	match season:
		WeatherManager.Season.SUMMER:
			if not Global.is_logged_in():
				rain.emitting = true
			
		WeatherManager.Season.AUTUMN:
			autumn_leaves.emitting = true

		WeatherManager.Season.WINTER:
			if not Global.is_logged_in():
				snow.emitting = true

		WeatherManager.Season.SPRING:
			spring_leaves.emitting = true

func _apply_world(state: Dictionary) -> void:
	if state.is_empty():
		return
	rain.emitting = state.get("weather", "clear") == "rain"
	snow.emitting = state.get("weather", "clear") == "snow"
