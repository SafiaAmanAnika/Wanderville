extends Node2D

signal season_changed(new_season)

enum Season {
	SUMMER,
	AUTUMN,
	WINTER,
	SPRING
}

var current_season: Season = Season.SUMMER
var days_in_season: int = 0
var days_per_season: int = 7

func _ready() -> void:
	var effects := get_node_or_null("../WeatherFXManager")
	if effects and effects.get_script() == null:
		effects.set_script(load("res://Scripts/weather_fx_manager.gd"))
		effects.initialize()
	GameState.world_updated.connect(_apply_world)
	_apply_world(GameState.world_state)
	season_changed.emit(current_season)

func on_new_day() -> void:
	if Global.is_logged_in():
		return
	days_in_season += 1
	
	if days_in_season >= days_per_season:
		days_in_season = 0
		current_season = (current_season + 1) % 4
		season_changed.emit(current_season)

func _apply_world(state: Dictionary) -> void:
	var seasons := {"summer": Season.SUMMER, "autumn": Season.AUTUMN, "winter": Season.WINTER, "spring": Season.SPRING}
	var next_season: int = seasons.get(state.get("current_season", "summer"), Season.SUMMER)
	if next_season != current_season:
		current_season = next_season
		season_changed.emit(current_season)
