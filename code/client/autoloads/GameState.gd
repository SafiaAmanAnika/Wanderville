extends Node

const MAX_WATER := 50

var water_drops: int = 10
var farm_zone_tilled: bool = false
var crop_tiles: Dictionary = {}
var menu_open: bool = false
var farm_mode: String = "none"
var selected_seed: String = ""

var seed_inventory: Dictionary = {
	"paddy": 5,
	"wheat": 5,
	"sugarcane": 5,
	"sweet_corn": 3,
	"bell_pepper": 3,
	"green_bean": 3,
	"pumpkin": 2,
	"apple": 2,
	"turnip": 2,
	"potato": 2,
	"carrot": 2,
	"cabbage": 2,
	"strawberry": 2,
	"lettuce": 3,
	"pea": 3,
	"radish": 3,
	"moonflower": 1,
	"rivermint": 1,
	"sunbloom": 1,
	"ancient_grain": 1
}

signal water_changed(new_amount: int)
signal mode_changed(new_mode: String)
signal seed_changed(new_seed: String)
signal data_loaded(success: bool)


func load_from_backend() -> void:
	if not Global.is_logged_in():
		data_loaded.emit(false)
		return

	var economy_res := await APIClient.get_economy(Global.token)
	if bool(economy_res.get("ok", false)):
		var body = economy_res.get("body", {})
		var data = body.get("data", {}) if typeof(body) == TYPE_DICTIONARY else {}
		if typeof(data) == TYPE_DICTIONARY:
			if data.has("taka_balance"):
				pass

	var inventory_res := await APIClient.get_inventory(Global.token)
	if bool(inventory_res.get("ok", false)):
		var body = inventory_res.get("body", {})
		var data = body.get("data", {}) if typeof(body) == TYPE_DICTIONARY else {}
		if typeof(data) == TYPE_DICTIONARY and data.has("items"):
			var items = data["items"]
			if typeof(items) == TYPE_ARRAY:
				seed_inventory.clear()
				for item in items:
					if typeof(item) == TYPE_DICTIONARY:
						var code = str(item.get("item_code", ""))
						var qty = int(item.get("quantity", 0))
						if code != "" and qty > 0:
							seed_inventory[code] = seed_inventory.get(code, 0) + qty

	var world_res := await APIClient.get_world_state(Global.token)
	if bool(world_res.get("ok", false)):
		var body = world_res.get("body", {})
		var data = body.get("data", {}) if typeof(body) == TYPE_DICTIONARY else {}
		if typeof(data) == TYPE_DICTIONARY and data.has("current_season"):
			pass

	var farm_res := await APIClient.get_farm_plots(Global.token)
	if bool(farm_res.get("ok", false)):
		var body = farm_res.get("body", {})
		var data = body.get("data", {}) if typeof(body) == TYPE_DICTIONARY else {}
		if typeof(data) == TYPE_DICTIONARY and data.has("plots"):
			var plots = data["plots"]
			if typeof(plots) == TYPE_ARRAY:
				for plot in plots:
					pass

	data_loaded.emit(true)


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
