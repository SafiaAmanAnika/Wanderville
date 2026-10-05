extends Node

const MAX_WATER := 20
var water_drops := 0
var farm_zone_tilled := false
var crop_tiles: Dictionary = {}
var menu_open := false
var social_open := false
var farm_mode := "none"
var selected_seed := ""
var seed_inventory: Dictionary = {}
var inventory: Array = []
var inventory_summary: Dictionary = {}
var profile: Dictionary = {}
var economy: Dictionary = {}
var experience: Dictionary = {}
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
signal gameplay_refreshed
signal economy_updated(data: Dictionary)
signal experience_updated(data: Dictionary)
signal level_advanced(previous: Dictionary, current: Dictionary)
signal store_requested


func reset() -> void:
	_loading = false
	_refreshing = false
	gameplay_refreshed.emit()
	data_loaded.emit(false)
	_poll_elapsed = 0.0
	backend_ready = false
	seed_inventory.clear()
	inventory.clear()
	inventory_summary.clear()
	inventory_updated.emit(inventory)
	farm_plots.clear()
	crop_tiles.clear()
	profile.clear()
	economy.clear()
	experience.clear()
	economy_updated.emit(economy)
	experience_updated.emit(experience)
	world_state.clear()
	water_drops = 0
	menu_open = false
	social_open = false
	farm_mode = "none"
	farm_zone_tilled = false
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
	var version := Global.session_version
	var success := true
	var requests: Array = [
		["/profile", "profile"], ["/world/me", "own_world"],
		["/economy/", "economy"], ["/inventory/", "inventory"],
		["/world/state", "world"], ["/farm/plots", "farm"], ["/economy/xp", "experience"]
	]
	for request in requests:
		var response: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_GET, request[0])
		if version != Global.session_version:
			return false
		if not bool(response.get("ok", false)):
			report_error(response)
			success = false
			break
		var data: Variant = APIClient.data_of(response)
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
			Global.selected_world_id = str(data.get("id", "")) if profile.get("map_code") == "campus" else ""
			Global.save_session()
		"economy":
			economy = data
			economy_updated.emit(data)
		"experience":
			var previous := experience
			experience = data
			experience_updated.emit(data)
			if not _loading and not previous.is_empty() and int(data.get("level", 1)) > int(previous.get("level", 1)):
				level_advanced.emit(previous, data)
		"inventory":
			inventory_summary = data
			inventory = data.get("items", [])
			seed_inventory.clear()
			for item in inventory:
				var code := str(item.get("item_code", ""))
				if code.ends_with("_seed"):
					var crop := code.trim_suffix("_seed")
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
	var version := Global.session_version
	while _refreshing:
		await gameplay_refreshed
		if version != Global.session_version:
			return
	if not Global.is_logged_in():
		return
	_refreshing = true
	# One round trip instead of six sequential reads. The bundle returns the
	# same sections as /farm/plots, /profile, /world/state, /inventory/,
	# /economy/ and /economy/xp, so the payloads applied below are unchanged.
	var response: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_GET, "/state/bundle")
	if version != Global.session_version:
		_refreshing = false
		return
	var data: Variant = APIClient.data_of(response)
	if not bool(response.get("ok", false)) or not data is Dictionary:
		report_error(response)
		_refreshing = false
		gameplay_refreshed.emit()
		return
	for section in ["farm", "profile", "world", "inventory", "economy", "experience"]:
		var payload: Variant = data.get(section)
		if not payload is Dictionary:
			report_error(response)
			_refreshing = false
			gameplay_refreshed.emit()
			return
		if section == "profile":
			# refresh_gameplay only tracks the bucket here; the rest of the
			# profile is applied once at sign-in by _apply_data("profile").
			water_drops = int(payload.get("water_charges", 0))
			water_changed.emit(water_drops)
		else:
			_apply_data(section, payload)
	_refreshing = false
	gameplay_refreshed.emit()


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
