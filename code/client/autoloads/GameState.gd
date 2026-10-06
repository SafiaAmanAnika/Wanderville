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
var owned_world: Dictionary = {}
var visit_session: Dictionary = {}
var read_only := false
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
signal session_updated(session: Dictionary)
signal read_only_changed(value: bool)
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
	owned_world.clear()
	visit_session.clear()
	_set_read_only(false)
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
		["/world/state", "world"], ["/farm/plots", "farm"], ["/economy/xp", "experience"],
		["/farm/visiting/session", "session"]
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
	if success:
		# The socket has to open in the world this player actually belongs to:
		# their own farm normally, or a host's farm while a visit is active. The
		# call is a no-op if the socket is not connected yet, because the desired
		# room is remembered and sent right after auth.
		APIClient.realtime.enter_world(desired_world_id())
	data_loaded.emit(success)
	return success


func _apply_data(kind: String, data: Dictionary) -> void:
	match kind:
		"profile":
			profile = data
			water_drops = int(data.get("water_charges", 0))
			water_changed.emit(water_drops)
			var code: Variant = data.get("character_code")
			if code == "player1" or code == "girl":
				Global.selected_character = "farmer_female"
			elif Global.CHARACTERS.has(str(code)):
				Global.selected_character = str(code)
			else:
				Global.selected_character = ""
			Global.display_name = str(data.get("display_name", Global.display_name))
			AudioManager.set_music_volume(float(data.get("music_volume", 80)))
			AudioManager.set_sfx_volume(float(data.get("effects_volume", 80)))
			Global.save_session()
		"own_world":
			owned_world = data
			Global.selected_world_id = str(data.get("id", "")) if profile.get("map_code") == "campus" else ""
			Global.save_session()
		"session":
			apply_session(data)
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


func is_visiting() -> bool:
	return str(visit_session.get("session_mode", "OWNER")) == "VISITOR"


func owning_world_id() -> int:
	return int(visit_session.get("owned_world_id", 0))


func current_world_id() -> int:
	return int(visit_session.get("current_world_id", owning_world_id()))


func desired_world_id() -> int:
	# Which world the socket should be standing in. The campus is where
	# everybody lives by default, so a player who is not visiting stays there
	# and only an accepted visit moves them into somebody else's world. Zero
	# means the campus; the server derives the room from it.
	return current_world_id() if is_visiting() else 0


func apply_session(session: Dictionary) -> void:
	visit_session = session
	# The server is the only authority on where this player is standing and on
	# whether they may write to the world. Read-only follows the session, never
	# the UI, so a visitor can never mutate the host's farm by any path.
	_set_read_only(is_visiting())
	session_updated.emit(visit_session)


func _set_read_only(value: bool) -> void:
	if read_only == value:
		return
	read_only = value
	read_only_changed.emit(read_only)


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
	# One round trip instead of seven sequential reads. The bundle returns the
	# same sections as /farm/plots, /profile, /world/state, /inventory/,
	# /economy/, /economy/xp and /farm/visiting/session, so the payloads applied
	# below are unchanged.
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
	for section in ["farm", "profile", "world", "inventory", "economy", "experience", "session"]:
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


# --- TEMP: dummy inventory for offline testing (remove later) ---
const DUMMY_ITEMS := [
	["river_carp", "River Carp", "fish", "fish", "common", 3],
	["golden_carp", "Golden Carp", "fish", "fish", "rare", 1],
	["pet_biscuit", "Pet Biscuit", "pet_food", "tools", "common", 10],
	["garden_lantern", "Garden Lantern", "decoration", "houses", "common", 2],
	["wheat_seed", "Wheat Seeds", "seed", "seeds", "common", 5],
	["carrot", "Carrot", "crop", "crops", "common", 4],
]


func load_dummy_inventory() -> void:
	inventory.clear()
	var partitions := {}
	var total := 0
	for i in DUMMY_ITEMS.size():
		var d: Array = DUMMY_ITEMS[i]
		inventory.append({
			"id": i, "item_code": d[0], "quantity": d[5], "partition": d[3],
			"item": {"name": d[1], "category": d[2], "rarity": d[4], "max_stack": 99, "description": "Dummy item for testing."},
		})
		partitions[d[3]] = int(partitions.get(d[3], 0)) + 1
		total += d[5]
	inventory_summary = {"items": inventory, "total_items": inventory.size(), "total_quantity": total, "partition_capacity": 20, "partitions": partitions}
	inventory_updated.emit(inventory)


# TEMP offline test: put an item in the local inventory (no server)
func add_item_offline(code: String, name: String, quantity := 1, partition := "crops") -> void:
	var found := false
	for row in inventory:
		if row["item_code"] == code:
			row["quantity"] = int(row["quantity"]) + quantity
			found = true
			break
	if not found:
		inventory.append({
			"id": "offline_" + code, "item_code": code, "quantity": quantity, "partition": partition,
			"item": {"name": name, "category": "crop", "rarity": "common", "max_stack": 99, "description": "Harvested %s." % name},
		})
		var parts: Dictionary = inventory_summary.get("partitions", {})
		parts[partition] = int(parts.get(partition, 0)) + 1
		inventory_summary["partitions"] = parts
	inventory_summary["items"] = inventory
	inventory_summary["total_items"] = inventory.size()
	inventory_summary["total_quantity"] = int(inventory_summary.get("total_quantity", 0)) + quantity
	inventory_updated.emit(inventory)
