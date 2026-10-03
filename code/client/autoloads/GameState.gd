extends Node

const MAX_WATER := 20
var water_drops := 0
var farm_zone_tilled := false
var crop_tiles: Dictionary = {}
var menu_open := false
var farm_mode := "none"
var selected_seed := ""
var seed_inventory: Dictionary = {}
var plantable_codes: Dictionary = {}
var catalog: Array = []
var inventory: Array = []
var profile: Dictionary = {}
var economy: Dictionary = {}
var world_state: Dictionary = {}
var farm_plots: Array = []
var backend_ready := false
var last_error := ""
var _loading := false
var _poll_elapsed := 0.0
var _refreshing := false
var _world_received_at := 0.0

signal water_changed(new_amount: int)
signal mode_changed(new_mode: String)
signal seed_changed(new_seed: String)
signal data_loaded(success: bool)
signal farm_updated(plots: Array)
signal world_updated(state: Dictionary)
signal inventory_updated(items: Array)
signal backend_error(message: String)


func reset() -> void:
	backend_ready = false
	_loading = false
	seed_inventory.clear()
	plantable_codes.clear()
	catalog.clear()
	inventory.clear()
	farm_plots.clear()
	crop_tiles.clear()
	profile.clear()
	economy.clear()
	world_state.clear()
	water_drops = 0
	menu_open = false
	selected_seed = ""
	water_changed.emit(0)


func report_error(response: Dictionary) -> void:
	last_error = APIClient.error_text(response)
	backend_error.emit(last_error)
	push_warning(last_error)


func load_from_backend() -> bool:
	if _loading:
		return await data_loaded
	if not Global.is_logged_in():
		return false
	_loading = true
	backend_ready = false
	var owner := Global.player_id
	var generation := Global.session_generation
	var success := true
	var requests: Array = [
		["/profile", "profile"], ["/world/me", "own_world"],
		["/economy/", "economy"], ["/inventory/catalog", "catalog"],
		["/inventory/", "inventory"], ["/world/state", "world"], ["/farm/plots", "farm"]
	]
	for request in requests:
		var response: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_GET, request[0])
		if owner != Global.player_id or generation != Global.session_generation:
			success = false
			break
		if not bool(response.get("ok", false)):
			report_error(response)
			success = false
			break
		var data: Variant = APIClient.data_of(response)
		if request[1] == "catalog" and data is Array:
			_apply_data(request[1], data)
			continue
		if not data is Dictionary:
			success = false
			last_error = "Server returned incomplete game data."
			break
		_apply_data(request[1], data)
	_loading = false
	backend_ready = success
	data_loaded.emit(success)
	return success


func _apply_data(kind: String, data: Dictionary) -> void:
	match kind:
		"profile":
			profile = data
			water_drops = int(data.get("water_charges", 0))
			water_changed.emit(water_drops)
			var code: Variant = data.get("character_code")
			Global.selected_character = "farmer_female" if code == "player1" or code == "girl" else ""
			Global.display_name = str(data.get("display_name", Global.display_name))
			AudioManager.set_music_volume(float(data.get("music_volume", 80)))
			AudioManager.set_sfx_volume(float(data.get("effects_volume", 80)))
			Global.save_session()
		"own_world":
			Global.selected_world_id = str(data.get("id", ""))
			Global.save_session()
		"catalog":
			catalog = data
			plantable_codes.clear()
			for item in catalog:
				var code := str(item.get("item_code", ""))
				var category := str(item.get("category", ""))
				if category.ends_with("_crop") or category == "rare_plant":
					plantable_codes[code] = true
		"economy":
			economy = data
		"inventory":
			inventory = data.get("items", [])
			seed_inventory.clear()
			for item in inventory:
				var code := str(item.get("item_code", ""))
				var crop := code.trim_suffix("_seed")
				if plantable_codes.has(crop) or code.ends_with("_seed"):
					seed_inventory[crop] = int(seed_inventory.get(crop, 0)) + int(item.get("quantity", 0))
			inventory_updated.emit(inventory)
			seed_changed.emit(selected_seed)
		"world":
			world_state = data
			_world_received_at = Time.get_ticks_msec() / 1000.0
			world_updated.emit(data)
		"farm":
			farm_plots = data.get("plots", [])
			farm_updated.emit(farm_plots)


func world_time_fraction() -> float:
	var duration := float(world_state.get("day_night_cycle_minutes", 40)) * 60.0
	var elapsed := Time.get_ticks_msec() / 1000.0 - _world_received_at
	return fposmod(float(world_state.get("current_time_of_day", 0.0)) + elapsed / duration, 1.0)


func _process(delta: float) -> void:
	if not backend_ready or _loading or not Global.is_logged_in():
		return
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path != SceneManager.WORLD_SCENE:
		return
	_poll_elapsed += delta
	if _poll_elapsed >= 3.0 and not _refreshing:
		_poll_elapsed = 0.0
		refresh_gameplay()


func refresh_gameplay() -> void:
	if _refreshing:
		return
	_refreshing = true
	var owner := Global.player_id
	var generation := Global.session_generation
	for request in [["/farm/plots", "farm"], ["/profile", "bucket"], ["/world/state", "world"], ["/inventory/", "inventory"], ["/economy/", "economy"]]:
		var response: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_GET, request[0])
		if owner != Global.player_id or generation != Global.session_generation:
			break
		var data: Variant = APIClient.data_of(response)
		if not bool(response.get("ok", false)) or not data is Dictionary:
			report_error(response)
			break
		if request[1] == "bucket":
			water_drops = int(data.get("water_charges", 0))
			water_changed.emit(water_drops)
		else:
			_apply_data(request[1], data)
	_refreshing = false


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
