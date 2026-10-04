extends Node

# Thin JSON HTTP client for the Wanderville backend.

const DEFAULT_BASE_URL := "http://127.0.0.1:8000"

var base_url: String = DEFAULT_BASE_URL
signal session_expired
signal refresh_finished(success: bool)
var _refreshing := false
var _refresh_version := -1
var realtime: Node


func _ready() -> void:
	var configured := OS.get_environment("WANDERVILLE_API_URL")
	if configured == "":
		configured = str(ProjectSettings.get_setting("network/wanderville_api_url", DEFAULT_BASE_URL))
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


func logout() -> Dictionary:
	var old_refresh := Global.refresh_token
	Global.clear_session()
	return await _request_once(HTTPClient.METHOD_POST, "/auth/logout", {"refresh_token": old_refresh}, {})


func refresh_session() -> bool:
	var version := Global.session_version
	if _refreshing and _refresh_version == version:
		var renewed: bool = await refresh_finished
		return renewed and version == Global.session_version
	if Global.refresh_token == "":
		return false
	_refreshing = true
	_refresh_version = version
	var old_refresh := Global.refresh_token
	var result := await _request_once(HTTPClient.METHOD_POST, "/auth/refresh", {"refresh_token": old_refresh}, {})
	var data: Variant = data_of(result)
	var success := bool(result.get("ok", false)) and data is Dictionary and version == Global.session_version and Global.refresh_token == old_refresh
	if success:
		Global.token = str(data.get("access_token", ""))
		Global.refresh_token = str(data.get("refresh_token", ""))
		Global.save_session()
	if _refresh_version == version:
		_refreshing = false
		refresh_finished.emit(success)
	return success


func _request_json(method: int, path: String, body: Variant, extra_headers: Dictionary) -> Dictionary:
	var headers := extra_headers.duplicate()
	var version := Global.session_version
	var used_token := Global.token
	if headers.has("Authorization") and used_token != "":
		headers["Authorization"] = "Bearer " + used_token
	var result := await _request_once(method, path, body, headers)
	if version != Global.session_version:
		return _stale_response()
	if int(result.get("status_code", 0)) == 401 and headers.has("Authorization"):
		var renewed := Global.token != used_token and Global.token != ""
		if not renewed:
			renewed = await refresh_session()
		if renewed and Global.session_version == version:
			headers["Authorization"] = "Bearer " + Global.token
			result = await _request_once(method, path, body, headers)
		elif version == Global.session_version:
			session_expired.emit()
	if version != Global.session_version:
		return _stale_response()
	return result


func _stale_response() -> Dictionary:
	return {"ok": false, "status_code": 0, "stale": true, "message": "The login session changed."}


func auth_config() -> Dictionary:
	return await _request_json(HTTPClient.METHOD_GET, "/auth/config", null, {})


func relocate_crop(plot_id: int, tile: Vector2i) -> Dictionary:
	return await authenticated(HTTPClient.METHOD_POST, "/farm/relocate", {"plot_id": plot_id, "x": tile.x, "y": tile.y})


func google_browser_login() -> Dictionary:
	var version := Global.session_version
	var config := await auth_config()
	if not config.get("ok", false):
		return config
	var client_id := str(data_of(config).get("google_client_id", ""))
	if client_id == "":
		return {"ok": false, "message": "Google sign-in needs a Desktop app client ID configured on the server."}
	var listener := TCPServer.new()
	if listener.listen(0, "127.0.0.1") != OK:
		return {"ok": false, "message": "Cannot open the local Google sign-in callback."}
	var redirect := "http://127.0.0.1:%d/oauth/callback" % listener.get_local_port()
	var crypto := Crypto.new()
	var verifier := crypto.generate_random_bytes(32).hex_encode()
	var state := crypto.generate_random_bytes(32).hex_encode()
	var nonce := crypto.generate_random_bytes(32).hex_encode()
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(verifier.to_utf8_buffer())
	var challenge := Marshalls.raw_to_base64(digest.finish()).replace("+", "-").replace("/", "_").rstrip("=")
	var params := {"client_id": client_id, "redirect_uri": redirect, "response_type": "code", "scope": "openid email profile", "state": state, "nonce": nonce, "code_challenge": challenge, "code_challenge_method": "S256"}
	var pairs: PackedStringArray = []
	for key in params:
		pairs.append(str(key) + "=" + str(params[key]).uri_encode())
	if OS.shell_open("https://accounts.google.com/o/oauth2/v2/auth?" + "&".join(pairs)) != OK:
		listener.stop()
		return {"ok": false, "message": "Cannot open your browser."}
	var deadline := Time.get_ticks_msec() + 120000
	var peer: StreamPeerTCP
	var received := ""
	var peer_deadline := 0
	var callback: Dictionary = {}
	while Time.get_ticks_msec() < deadline and version == Global.session_version:
		if peer == null and listener.is_connection_available():
			peer = listener.take_connection()
			peer_deadline = Time.get_ticks_msec() + 3000
		if peer != null:
			peer.poll()
			if peer.get_available_bytes() > 0:
				received += peer.get_utf8_string(peer.get_available_bytes())
			if received.contains("\r\n\r\n"):
				var line := received.get_slice("\r\n", 0)
				var path := line.get_slice(" ", 1)
				if line.begins_with("GET /oauth/callback?"):
					callback = Global._parse_query(path.get_slice("?", 1))
				var valid := str(callback.get("state", "")) == state
				var message := "Return to Wanderville to finish signing in." if valid else "Invalid sign-in callback."
				peer.put_data(("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: %d\r\n\r\n%s" % [message.length(), message]).to_utf8_buffer())
				peer.disconnect_from_host()
				peer = null
				received = ""
				if valid:
					break
				callback.clear()
			elif received.length() > 8192 or Time.get_ticks_msec() > peer_deadline:
				peer.disconnect_from_host()
				peer = null
				received = ""
		await get_tree().process_frame
	listener.stop()
	if peer != null:
		peer.disconnect_from_host()
	if version != Global.session_version:
		return _stale_response()
	if not callback.has("code"):
		return {"ok": false, "message": "Google sign-in was cancelled or timed out. Please try again."}
	return await _request_json(HTTPClient.METHOD_POST, "/auth/google/code", {"code": callback["code"], "code_verifier": verifier, "redirect_uri": redirect, "nonce": nonce}, {})


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
	var json := JSON.new()
	var parsed: Variant = null
	if not bytes.is_empty() and json.parse(bytes.get_string_from_utf8()) == OK:
		parsed = json.data
	var succeeded := int(response[0]) == HTTPRequest.RESULT_SUCCESS and status >= 200 and status < 300 and parsed is Dictionary
	return {"ok": succeeded, "status_code": status, "body": parsed}
