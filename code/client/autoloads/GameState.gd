extends Node

var water_drops: int = 0

var farm_zone_tilled: bool = false
var crop_tiles: Dictionary = {}

var menu_open: bool = false
var farm_mode: String = "none"

var selected_seed: String = "" 
var seed_inventory: Dictionary = {
	"wheat": 5,
	"corn": 3,
	"cotton": 2,
	"tulip": 2
}

signal water_changed(new_amount: int)
signal mode_changed(new_mode: String)
signal seed_changed(new_seed: String)

func add_water(amount: int) -> void:
	water_drops += amount
	water_changed.emit(water_drops)

func spend_water(amount: int) -> bool:
	if water_drops >= amount:
		water_drops -= amount
		water_changed.emit(water_drops)
		
		return true
	return false

func set_mode(mode: String) -> void:
	farm_mode = mode
	mode_changed.emit(mode)

func set_seed(seed: String) -> void:
	selected_seed = seed
	seed_changed.emit(seed)
