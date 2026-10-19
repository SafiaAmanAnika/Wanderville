extends RefCounted
class_name BackendBridge
## The Godot dedicated server's private channel to the Python backend.
##
## This is the only place the server learns who a peer is. It carries a
## server-only secret that is read from the environment at runtime and is never
## part of the client export, never logged, and never sent to a game client.
##
## Only two things are ever asked of the backend: is it reachable, and what
## player does this ticket belong to. There is deliberately no "trust this peer"
## call, because the whole security property is that the backend decides.

var _base_url := "http://127.0.0.1:8000"
var _secret := ""
## HTTPRequest only polls while it is inside the tree, so the bridge needs a
## parent. Without one the request never completes and every await below hangs.
var _parent: Node


func _init(base_url := "", secret := "", parent: Node = null) -> void:
	# Order matters: resolve the environment first, then let an explicit
	# argument override it. Done the other way round the default would always
	# win and a configured host could never be overridden.
	if secret != "":
		_secret = secret
	else:
		_secret = OS.get_environment("MULTIPLAYER_BRIDGE_SECRET")
	if base_url != "":
		_base_url = base_url
	else:
		var configured := OS.get_environment("MULTIPLAYER_BRIDGE_URL")
		if configured != "":
			_base_url = configured
	_parent = parent


func configured() -> bool:
	return _secret != ""


func base_url() -> String:
	return _base_url


## Confirm the backend is reachable and this host is allowed before listening.
func health() -> Dictionary:
	return await _post("/internal/multiplayer/health", {})


## Spend a ticket. The reply is the authoritative identity for the peer.
func consume(ticket: String, server_id := "") -> Dictionary:
	if ticket == "":
		return {"ok": false, "error": "MISSING_TICKET"}
	return await _post(
		"/internal/multiplayer/tickets/consume",
		{"ticket": ticket, "server_id": server_id},
	)


func introspect(ticket: String, server_id := "") -> Dictionary:
	return await _post(
		"/internal/multiplayer/tickets/introspect",
		{"ticket": ticket, "server_id": server_id},
	)


## Publish the authoritative campus positions the server just simulated.
##
## The WebSocket presence path only ever learns a position when a client sends
## one, and an ENet client never does -- the server owns the position instead. So
## without this call every ENet player is present in the database but frozen at
## their spawn for everyone else's roster and proximity. This sends positions to
## the in-memory projection only; it is not a per-step database write.
##
## ``leaves`` lists players that just left, so a disconnect drops the neighbour
## immediately rather than waiting for the projection's TTL.
func push_presence(updates: Array, leaves: Array, server_id := "") -> Dictionary:
	return await _post(
		"/internal/multiplayer/presence",
		{"updates": updates, "leaves": leaves, "server_id": server_id},
	)


func _post(path: String, payload: Dictionary) -> Dictionary:
	if not configured():
		return {
			"ok": false,
			"error": "BRIDGE_NOT_CONFIGURED",
			"detail": "Set MULTIPLAYER_BRIDGE_SECRET for the multiplayer server.",
		}
	var request := HTTPRequest.new()
	if _parent != null:
		_parent.add_child(request)
	var body := JSON.stringify(payload)
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json",
		"X-Multiplayer-Secret: " + _secret,
	])
	var error := request.request(
		_base_url.rstrip("/") + path,
		headers,
		HTTPClient.METHOD_POST,
		body,
	)
	if error != OK:
		request.queue_free()
		return {"ok": false, "error": "REQUEST_FAILED", "detail": str(error)}

	var response: Array = await request.request_completed
	# request_completed returns (result, response_code, headers, body).
	var result := int(response[0])
	var code := int(response[1])
	var raw := PackedByteArray(response[3])
	request.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS:
		# Distinguish "never reached the backend" from "reached it and was
		# refused": the two need completely different investigations.
		return {
			"ok": false,
			"error": "TRANSPORT_FAILED",
			"detail": "result=%d url=%s" % [result, _base_url.rstrip("/") + path],
		}

	var text := raw.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	var body_dict: Dictionary = parsed if parsed is Dictionary else {}
	if code != 200:
		var message := str(body_dict.get("message", "request rejected"))
		# Never echo the ticket: a rejection must not write it into a log.
		return {"ok": false, "error": "REJECTED", "status": code, "detail": message}
	var data: Dictionary = body_dict.get("data", {})
	data["ok"] = true
	return data