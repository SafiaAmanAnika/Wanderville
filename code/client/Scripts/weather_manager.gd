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
	season_changed.emit(current_season)

func on_new_day() -> void:
	days_in_season += 1
	
	if days_in_season >= days_per_season:
		days_in_season = 0
		current_season = (current_season + 1) % 4
		season_changed.emit(current_season)
