extends Node

const MAX_WATER := 50

var water_drops: int = 10
var farm_zone_tilled: bool = false
var crop_tiles: Dictionary = {}
var menu_open: bool = false
var farm_mode: String = "none"
var selected_seed: String = ""

var seed_inventory: Dictionary = {
	# 🍃 General Purpose Crops
	"paddy": 5,
	"wheat": 5,
	"sugarcane": 5,

	# 🌞 Summer
	"sweet_corn": 3,
	"bell_pepper": 3,
	"green_bean": 3,

	# 🍂 Autumn
	"pumpkin": 2,
	"apple": 2,
	"turnip": 2,

	# ❄️ Winter
	"potato": 2,
	"carrot": 2,
	"cabbage": 2,
	"strawberry": 2,

	# 🌱 Spring
	"lettuce": 3,
	"pea": 3,
	"radish": 3,

	# 🪄 Rare Plants
	"moonflower": 1,
	"rivermint": 1,
	"sunbloom": 1,
	"ancient_grain": 1
}

signal water_changed(new_amount: int)
signal mode_changed(new_mode: String)
signal seed_changed(new_seed: String)

func spend_water(amount: int) -> bool:
	if water_drops >= amount:
		water_drops -= amount
		water_changed.emit(water_drops)
		return true
	return false

func add_water(amount: int) -> void:
	water_drops = clampi(water_drops + amount, 0, MAX_WATER)
	water_changed.emit(water_drops)

func set_mode(mode: String) -> void:
	farm_mode = mode
	mode_changed.emit(mode)

func set_seed(seed: String) -> void:
	selected_seed = seed
	seed_changed.emit(seed)
