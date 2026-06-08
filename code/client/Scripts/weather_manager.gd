extends Node2D

enum Season {
	SUMMER,
	AUTUMN,
	WINTER,
	SPRING
}

var current_season = Season.SUMMER 
var days_in_season = 0

@onready var rain: GPUParticles2D = $"../Rain"
@onready var snow: GPUParticles2D = $"../Snow"

func _ready():
	rain.emitting = false
	snow.emitting = false
	weather_loop()

func weather_loop() -> void:
	while true: 
		await get_tree().create_timer(300.0).timeout
		
		match current_season:
			Season.SUMMER:
				rain.emitting = true
				snow.emitting = false
				await get_tree().create_timer(30.0).timeout
				rain.emitting = false
			
			Season.WINTER:
				snow.emitting = true
				rain.emitting = false
				await get_tree().create_timer(30.0).timeout
				snow.emitting = false
			
			_:
				rain.emitting = false
				snow.emitting = false

func on_new_day() -> void:
	days_in_season += 1
	
	if days_in_season >= 7:
		days_in_season = 0
		current_season = (current_season + 1) % 4
