extends Node

# Thin JSON HTTP client for the Wanderville backend.

const DEFAULT_BASE_URL := "http://127.0.0.1:8000"

var base_url: String = DEFAULT_BASE_URL
signal session_expired
signal refresh_finished(success: bool)
var _refreshing := false
var realtime: Node


func _ready() -> void:
	var configured := OS.get_environment("WANDERVILLE_API_URL")
	if configured != "":
		base_url = configured.rstrip("/")
	realtime = preload("res://autoloads/RealtimeClient.gd").new()
	realtime.name = "RealtimeClient"
	add_child(realtime)


# ── Auth endpoints ──────────────────────────────────────────────────

func login(username: String, password: String) -> Dictionary:
	return await _request_json(
		HTTPClient.METHOD_POST,
		"/auth/login",
		{"username": username, "password": password},
		{}
	)


func signup(username: String, email: String, password: String, display_name: String = "") -> Dictionary:
	var body := {
		"username": username,
		"email": email,
		"password": password,
	}
	if display_name != "":
		body["display_name"] = display_name
	return await _request_json(
		HTTPClient.METHOD_POST,
		"/auth/signup",
		body,
		{}
	)


func google_login(id_token: String) -> Dictionary:
	return await _request_json(
		HTTPClient.METHOD_POST,
		"/auth/google",
		{"id_token": id_token},
		{}
	)


func forgot_password(email: String) -> Dictionary:
	return await _request_json(
		HTTPClient.METHOD_POST,
		"/auth/forgot-password",
		{"email": email},
		{}
	)


func verify_email(token: String) -> Dictionary:
	return await _request_json(
		HTTPClient.METHOD_GET,
		"/auth/verify-email?token=" + token.uri_encode(),
		null,
		{}
	)


func resend_verification(email: String) -> Dictionary:
	return await _request_json(
		HTTPClient.METHOD_POST,
		"/auth/resend-verification",
		{"email": email},
		{}
	)


func reset_password(token: String, new_password: String) -> Dictionary:
	return await _request_json(
		HTTPClient.METHOD_POST,
		"/auth/reset-password",
		{"token": token, "new_password": new_password},
		{}
	)


func me(token: String) -> Dictionary:
	return await _request_json(
		HTTPClient.METHOD_GET,
		"/auth/me",
		null,
		{"Authorization": "Bearer %s" % token}
	)


# ── Inventory endpoints ─────────────────────────────────────────────

func get_inventory(token: String) -> Dictionary:
	return await _request_json(
		HTTPClient.METHOD_GET,
		"/inventory/",
		null,
		{"Authorization": "Bearer %s" % token}
	)


func get_catalog(token: String) -> Dictionary:
	return await _request_json(
		HTTPClient.METHOD_GET,
		"/inventory/catalog",
		null,
		{"Authorization": "Bearer %s" % token}
	)


func add_item(token: String, item_code: String, quantity: int = 1, location: String = "inventory") -> Dictionary:
	return await _request_json(
		HTTPClient.METHOD_POST,
		"/inventory/add",
		{"item_code": item_code, "quantity": quantity, "location": location},
		{"Authorization": "Bearer %s" % token}
	)


func remove_item(token: String, item_code: String, quantity: int = 1) -> Dictionary:
	return await _request_json(
		HTTPClient.METHOD_POST,
		"/inventory/remove",
		{"item_code": item_code, "quantity": quantity},
		{"Authorization": "Bearer %s" % token}
	)


# ── Economy endpoints ───────────────────────────────────────────────

func get_economy(token: String) -> Dictionary:
	return await _request_json(
		HTTPClient.METHOD_GET,
		"/economy/",
		null,
		{"Authorization": "Bearer %s" % token}
	)


func earn_taka(token: String, amount: int, description: String = "") -> Dictionary:
	return await _request_json(
		HTTPClient.METHOD_POST,
		"/economy/earn",
		{"amount": amount, "currency_type": "taka", "description": description},
		{"Authorization": "Bearer %s" % token}
	)


func spend_taka(token: String, amount: int, description: String = "") -> Dictionary:
	return await _request_json(
		HTTPClient.METHOD_POST,
		"/economy/spend",
		{"amount": amount, "currency_type": "taka", "description": description},
		{"Authorization": "Bearer %s" % token}
	)


func get_xp(token: String) -> Dictionary:
	return await _request_json(
		HTTPClient.METHOD_GET,
		"/economy/xp",
		null,
		{"Authorization": "Bearer %s" % token}
	)


func gain_xp(token: String, xp_amount: int, source: String = "") -> Dictionary:
	return await _request_json(
		HTTPClient.METHOD_POST,
		"/economy/xp/gain",
		{"xp_amount": xp_amount, "source": source},
		{"Authorization": "Bearer %s" % token}
	)


# ── World endpoints ─────────────────────────────────────────────────

func get_my_world(token: String) -> Dictionary:
	return await _request_json(
		HTTPClient.METHOD_GET,
		"/world/me",
		null,
		{"Authorization": "Bearer %s" % token}
	)


func get_world_state(token: String) -> Dictionary:
	return await _request_json(
		HTTPClient.METHOD_GET,
		"/world/state",
		null,
		{"Authorization": "Bearer %s" % token}
	)


# ── Farm endpoints ──────────────────────────────────────────────────

func get_farm_plots(token: String) -> Dictionary:
	return await _request_json(
		HTTPClient.METHOD_GET,
		"/farm/plots",
		null,
		{"Authorization": "Bearer %s" % token}
	)


func plant_crop(token: String, x: int, y: int, item_code: String) -> Dictionary:
	return await _request_json(
		HTTPClient.METHOD_POST,
		"/farm/plant",
		{"x": x, "y": y, "item_code": item_code},
		{"Authorization": "Bearer %s" % token}
	)


func water_crop(token: String, plot_id: int) -> Dictionary:
	return await _request_json(
		HTTPClient.METHOD_POST,
		"/farm/water",
		{"plot_id": plot_id},
		{"Authorization": "Bearer %s" % token}
	)


func harvest_crop(token: String, plot_id: int) -> Dictionary:
	return await _request_json(
		HTTPClient.METHOD_POST,
		"/farm/harvest",
		{"plot_id": plot_id},
		{"Authorization": "Bearer %s" % token}
	)


# ── HTTP internals ──────────────────────────────────────────────────

func data_of(response: Dictionary) -> Variant:
	var body: Variant = response.get("body")
	return body.get("data") if body is Dictionary else null


func error_text(response: Dictionary) -> String:
	var body: Variant = response.get("body")
	if body is Dictionary:
		return str(body.get("message", body.get("detail", "Request failed")))
	return str(response.get("message", "Cannot reach the server. Please try again."))


func authenticated(method: int, path: String, body: Variant = null) -> Dictionary:
	return await _request_json(method, path, body, {"Authorization": "Bearer " + Global.token})


func get_profile() -> Dictionary:
	return await authenticated(HTTPClient.METHOD_GET, "/profile")


func update_profile(values: Dictionary) -> Dictionary:
	return await authenticated(HTTPClient.METHOD_PUT, "/profile", values)


func till_tile(x: int, y: int) -> Dictionary:
	return await authenticated(HTTPClient.METHOD_POST, "/farm/till", {"x": x, "y": y})


func refill_water() -> Dictionary:
	return await authenticated(HTTPClient.METHOD_POST, "/farm/refill")


func send_direct_message(target_id: int, message: String) -> Dictionary:
	return await authenticated(HTTPClient.METHOD_POST, "/social/messages", {"target_id": target_id, "body": message})


func get_direct_messages(target_id: int, after: int = 0) -> Dictionary:
	return await authenticated(HTTPClient.METHOD_GET, "/social/messages/%d?after=%d" % [target_id, after])


func search_players(query: String) -> Dictionary:
	return await authenticated(HTTPClient.METHOD_GET, "/social/search?q=" + query.uri_encode())


func get_friends() -> Dictionary:
	return await authenticated(HTTPClient.METHOD_GET, "/social/friends")


func get_private_farm(target_id: int) -> Dictionary:
	return await authenticated(HTTPClient.METHOD_GET, "/social/farms/%d" % target_id)


func send_nearby_chat(message: String) -> bool:
	return realtime.send_nearby_chat(message)


func send_emote(emote: String) -> bool:
	return realtime.send_emote(emote)


func logout() -> Dictionary:
	realtime.stop()
	var result := await _request_once(HTTPClient.METHOD_POST, "/auth/logout", {"refresh_token": Global.refresh_token}, {})
	Global.clear_session()
	return result


func refresh_session() -> bool:
	if _refreshing:
		return await refresh_finished
	if Global.refresh_token == "":
		return false
	_refreshing = true
	var old_refresh := Global.refresh_token
	var result := await _request_once(HTTPClient.METHOD_POST, "/auth/refresh", {"refresh_token": old_refresh}, {})
	var data: Variant = data_of(result)
	var success := bool(result.get("ok", false)) and data is Dictionary and Global.refresh_token == old_refresh
	if success:
		Global.token = str(data.get("access_token", ""))
		Global.refresh_token = str(data.get("refresh_token", ""))
		Global.save_session()
	_refreshing = false
	refresh_finished.emit(success)
	return success


func _request_json(method: int, path: String, body: Variant, extra_headers: Dictionary) -> Dictionary:
	var headers := extra_headers.duplicate()
	var session_id := Global.player_id
	var session_generation := Global.session_generation
	var used_token := Global.token
	if headers.has("Authorization") and used_token != "":
		headers["Authorization"] = "Bearer " + used_token
	var result := await _request_once(method, path, body, headers)
	if int(result.get("status_code", 0)) == 401 and headers.has("Authorization") and Global.player_id == session_id and Global.session_generation == session_generation:
		var renewed := Global.token != used_token and Global.token != ""
		if not renewed:
			renewed = await refresh_session()
		if renewed and Global.player_id == session_id and Global.session_generation == session_generation:
			headers["Authorization"] = "Bearer " + Global.token
			return await _request_once(method, path, body, headers)
		session_expired.emit()
	return result


func _request_once(method: int, path: String, body: Variant, extra_headers: Dictionary) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 15.0
	add_child(http)
	var headers: PackedStringArray = ["Content-Type: application/json", "Accept: application/json"]
	for key in extra_headers:
		headers.append("%s: %s" % [key, extra_headers[key]])
	var payload := "" if body == null else JSON.stringify(body)
	var err := http.request(base_url.rstrip("/") + path, headers, method, payload)
	if err != OK:
		http.queue_free()
		return {"ok": false, "status_code": 0, "message": "Unable to start request", "body": null}
	var response: Array = await http.request_completed
	http.queue_free()
	var status := int(response[1])
	var bytes: PackedByteArray = response[3]
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	var succeeded := int(response[0]) == HTTPRequest.RESULT_SUCCESS and status >= 200 and status < 300 and parsed is Dictionary
	return {"ok": succeeded, "status_code": status, "body": parsed}
