extends Node2D

const SAVE_PATH := "user://seasonal_state.cfg"

# Real-world durations in seconds
const SEASON_DURATION: float = 24.0 * 60.0 * 60.0 #24 hours
const RAIN_INTERVAL: float = 15.0 * 60.0 #15 mins
const RAIN_DURATION: float = 2.0 * 60.0 #2 mins
const SAVE_INTERVAL: float = 30.0 #30 sec

enum Season {
	SUMMER, AUTUMN, WINTER, SPRING
}

var current_season: int = Season.SUMMER
var season_elapsed_time: float = 0.0
var rain_elapsed_time: float = 0.0
var save_timer: float = 0.0

@onready var rain: GPUParticles2D = $Rain
@onready var snow: GPUParticles2D = $Snow
@onready var autumn_leaves: GPUParticles2D = $Autumn_leaves
@onready var spring_leaves: GPUParticles2D = $Spring_leaves


func _ready() -> void:
	load_state()

	# Account for real time spent outside the game.
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		var last_saved: float = config.get_value("state", "last_saved_unix", 0.0)
		var now: float = Time.get_unix_time_from_system()

		if last_saved > 0.0:
			var offline_seconds: float = maxf(0.0, now - last_saved)
			advance_time(offline_seconds)

	update_season_effects()
	update_rain()
	save_state()


func _process(delta: float) -> void:
	advance_time(delta)

	save_timer += delta
	if save_timer >= SAVE_INTERVAL:
		save_timer = 0.0
		save_state()


func advance_time(seconds: float) -> void:
	season_elapsed_time += seconds
	rain_elapsed_time += seconds

	# Advance through as many seasons as necessary.
	var seasons_passed: int = int(floor(season_elapsed_time / SEASON_DURATION))

	if seasons_passed > 0:
		season_elapsed_time = fmod(season_elapsed_time, SEASON_DURATION)
		current_season = (current_season + seasons_passed) % 4

		update_season_effects()

	update_rain()

func update_season_effects() -> void:
	# Only the current season's effect is enabled
	snow.emitting = current_season == Season.WINTER
	autumn_leaves.emitting = current_season == Season.AUTUMN
	spring_leaves.emitting = current_season == Season.SPRING

	# Rain is controlled separately by its schedule.
	update_rain()
	
	var tree_manager = get_node_or_null("../Map/Trees")

	if tree_manager != null:
		tree_manager.set_tree_season(current_season)


func update_rain() -> void:
	var rain_cycle := fmod(rain_elapsed_time, RAIN_INTERVAL)
	var rain_scheduled := (rain_elapsed_time >= RAIN_INTERVAL and rain_cycle < RAIN_DURATION)
	rain.emitting = (current_season == Season.SUMMER and rain_scheduled)


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
	
	return "Unknown"


func get_current_season() -> Season:
	return current_season

func save_state() -> void:
	var config := ConfigFile.new()

	config.set_value("state", "season", current_season)
	config.set_value("state", "season_elapsed_time", season_elapsed_time)
	config.set_value("state", "rain_elapsed_time", rain_elapsed_time)
	config.set_value("state", "last_saved_unix", Time.get_unix_time_from_system())

	var error := config.save(SAVE_PATH)
	if error != OK:
		push_warning("Could not save seasonal state.")


func load_state() -> void:
	var config := ConfigFile.new()
	var error := config.load(SAVE_PATH)

	if error != OK:
		# First launch: start in summer.
		current_season = Season.SUMMER
		season_elapsed_time = 0.0
		rain_elapsed_time = 0.0
		return

	current_season = int(config.get_value("state", "season", Season.SUMMER)) % 4
	season_elapsed_time = float(config.get_value("state", "season_elapsed_time", 0.0))
	rain_elapsed_time = float(config.get_value("state", "rain_elapsed_time", 0.0))


func _exit_tree() -> void:
	save_state()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_state()
