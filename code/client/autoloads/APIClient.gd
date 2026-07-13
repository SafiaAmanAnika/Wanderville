extends Node

# Thin JSON HTTP client for the Wanderville backend.

const DEFAULT_BASE_URL := "http://127.0.0.1:8000"

var base_url: String = DEFAULT_BASE_URL
var _http: HTTPRequest


func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)


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

func _request_json(method: int, path: String, body: Variant, extra_headers: Dictionary) -> Dictionary:
	var url := base_url.rstrip("/") + path
	var headers: PackedStringArray = ["Content-Type: application/json", "Accept: application/json"]
	for k in extra_headers.keys():
		headers.append("%s: %s" % [str(k), str(extra_headers[k])])

	var payload := ""
	if body != null:
		payload = JSON.stringify(body)

	var err := _http.request(url, headers, method, payload)
	if err != OK:
		return {
			"ok": false,
			"status_code": 0,
			"error": "REQUEST_FAILED",
			"message": "HTTPRequest.request failed: %s" % str(err),
			"body": null,
		}

	var result: Array = await _http.request_completed
	var response_code := int(result[1])
	var response_bytes: PackedByteArray = result[3]
	var response_text := response_bytes.get_string_from_utf8()

	var parsed: Variant = null
	if response_text != "":
		parsed = JSON.parse_string(response_text)

	var is_ok := response_code >= 200 and response_code < 300
	return {
		"ok": is_ok,
		"status_code": response_code,
		"body": parsed,
		"raw_text": response_text,
	}
