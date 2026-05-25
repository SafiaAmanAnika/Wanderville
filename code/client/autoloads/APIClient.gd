extends Node

# Thin JSON HTTP client for the Wanderville backend.

const DEFAULT_BASE_URL := "http://127.0.0.1:8000"

var base_url: String = DEFAULT_BASE_URL
var _http: HTTPRequest


func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)


func login(username: String, password: String) -> Dictionary:
	return await _request_json(
		HTTPClient.METHOD_POST,
		"/auth/login",
		{"username": username, "password": password},
		{}
	)


func signup(username: String, password: String, display_name: String) -> Dictionary:
	return await _request_json(
		HTTPClient.METHOD_POST,
		"/auth/signup",
		{"username": username, "password": password, "display_name": display_name},
		{}
	)


func me(token: String) -> Dictionary:
	return await _request_json(
		HTTPClient.METHOD_GET,
		"/auth/me",
		null,
		{"Authorization": "Bearer %s" % token}
	)


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
