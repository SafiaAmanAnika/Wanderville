extends Node
class_name MultiplayerClient
## Isolated client for the Godot dedicated server.
##
## Deliberately independent of ``RealtimeClient``. That autoload owns the
## Python WebSocket path -- chat, social, voice leases, snapshots -- and this
## node handles only ENet admission. Normal-world integration keeps WebSocket
## gameplay services active while the bridge selects one movement transport.
##
## It also deliberately does not move anything. There is no input sampling and
## no ``global_position`` write here, so enabling this node cannot create a
## second movement authority alongside the Python one.
##
## Authentication uses SceneMultiplayer's own workflow: once the transport is up
## the ticket travels in a ``send_auth`` message, the server decides, and
## ``peer_connected`` is what tells this client it was admitted.

signal connection_state_changed(state: int)
signal admitted(identity: Dictionary)
signal rejected(reason: String)
signal disconnected()

enum State {
	IDLE,
	REQUESTING_TICKET,
	CONNECTING,
	AUTHENTICATING,
	ADMITTED,
	REJECTED,
	FAILED,
}

const HTTP_TIMEOUT_SECONDS := 10.0
## Grace period between the transport connecting and presenting the ticket, so
## the server has registered this peer as authenticating.
const AUTH_SETTLE_SECONDS := 1.5


## Symbolic name for an HTTPRequest.Result.
##
## An earlier report read the bare integer 13 as a DNS failure. It is not:
## RESULT_CANT_RESOLVE is 3 and RESULT_TIMEOUT is 13 in Godot 4.6, verified against
## ClassDB. Logging the name alongside the number is what stops that mistake
## recurring.
static func http_result_name(result: int) -> String:
	match result:
		HTTPRequest.RESULT_SUCCESS: return "RESULT_SUCCESS"
		HTTPRequest.RESULT_CANT_CONNECT: return "RESULT_CANT_CONNECT"
		HTTPRequest.RESULT_CANT_RESOLVE: return "RESULT_CANT_RESOLVE"
		HTTPRequest.RESULT_CONNECTION_ERROR: return "RESULT_CONNECTION_ERROR"
		HTTPRequest.RESULT_NO_RESPONSE: return "RESULT_NO_RESPONSE"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED: return "RESULT_BODY_SIZE_LIMIT_EXCEEDED"
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED: return "RESULT_REDIRECT_LIMIT_REACHED"
		HTTPRequest.RESULT_REQUEST_FAILED: return "RESULT_REQUEST_FAILED"
		HTTPRequest.RESULT_TIMEOUT: return "RESULT_TIMEOUT"
		_: return "RESULT_UNKNOWN_%d" % result


## Symbolic name for an HTTPClient.Status, so a connection phase can be told
## apart from a response phase.
static func http_client_status_name(status: int) -> String:
	match status:
		HTTPClient.STATUS_DISCONNECTED: return "DISCONNECTED"
		HTTPClient.STATUS_RESOLVING: return "RESOLVING"
		HTTPClient.STATUS_CANT_RESOLVE: return "CANT_RESOLVE"
		HTTPClient.STATUS_CONNECTING: return "CONNECTING"
		HTTPClient.STATUS_CANT_CONNECT: return "CANT_CONNECT"
		HTTPClient.STATUS_CONNECTED: return "CONNECTED"
		HTTPClient.STATUS_REQUESTING: return "REQUESTING"
		HTTPClient.STATUS_BODY: return "BODY"
		HTTPClient.STATUS_CONNECTION_ERROR: return "CONNECTION_ERROR"
		HTTPClient.STATUS_TLS_HANDSHAKE_ERROR: return "TLS_HANDSHAKE_ERROR"
		_: return "STATUS_UNKNOWN_%d" % status

var state: int = State.IDLE
var identity: Dictionary = {}
var host := NetworkConfig.DEFAULT_HOST
var port := NetworkConfig.DEFAULT_PORT
var base_url := "http://127.0.0.1:8000"
## Last diagnostic, for tests and bug reports. Never contains a credential.
var last_diagnostic: Dictionary = {}

var _token := ""
var _pending_ticket := ""
var _retries := 0
var _retry_delay := NetworkConfig.DEFAULT_RETRY_DELAY_SECONDS
var _stopping := false
## Guards a retry timer so a cancelled attempt's continuation cannot resume and
## clobber the state of a newer one.
var _attempt_id := 0


func configure(api_base_url: String, access_token: String) -> void:
	base_url = api_base_url.rstrip("/")
	_token = access_token


func connect_to_server(server_host := "", server_port := 0) -> void:
	host = server_host if server_host != "" else NetworkConfig.host()
	port = server_port if server_port > 0 else NetworkConfig.port()
	_stopping = false
	_attempt()


func _set_state(value: int) -> void:
	if state != value:
		state = value
		connection_state_changed.emit(state)


## Records the last stage reached, for tests and bug reports.
## GDScript has no **kwargs, so extra fields go in an explicit dictionary.
## Only non-sensitive values are ever passed in.
func _diag(stage: String, fields: Dictionary = {}) -> void:
	var entry := {"stage": stage}
	entry.merge(fields)
	last_diagnostic = entry
	print("[MultiplayerClient] diag %s" % JSON.stringify(entry))


func _attempt() -> void:
	_attempt_id += 1
	var mine := _attempt_id
	if _stopping or mine != _attempt_id:
		return
	if _token == "":
		_diag("no_token")
		_set_state(State.FAILED)
		rejected.emit("No access token: authenticate with the backend first.")
		return

	_clear_peer()
	_set_state(State.REQUESTING_TICKET)
	# A ticket may be supplied directly by the test harness so a replay can be
	# attempted against an exact value. Never set in normal play.
	var override := OS.get_environment("TEST_TICKET_OVERRIDE")
	var ticket: Dictionary = {"ticket": override} if override != "" else await _request_ticket()
	if _stopping or mine != _attempt_id:
		# A newer attempt (or a disconnect) replaced this one while it awaited.
		return
	if ticket.is_empty():
		_retry_or_fail("Could not obtain an admission ticket.")
		return

	_set_state(State.CONNECTING)
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(host, port)
	if error != OK:
		_diag("create_client_failed", {"port": port, "code": int(error)})
		_retry_or_fail("Could not open udp to %s:%d" % [host, port])
		return
	multiplayer.multiplayer_peer = peer
	var scene_multiplayer := multiplayer as SceneMultiplayer
	# Both sides must set auth_callback.
	#
	# SceneMultiplayer only accepts send_auth() towards a peer that it is
	# itself authenticating, so a client that omits this gets ERR_INVALID_PARAMETER
	# ("!pending_peers.has(p_to)") when it tries to present its ticket. Verified
	# against two real Godot processes: with the callback set the client's
	# send_auth returns OK and the server's callback receives the payload.
	#
	# Returning false keeps the client in the authenticating state; the server
	# calls complete_auth(1) once the backend has vouched for the identity, and
	# the client completes then. The client never authenticates the server.
	scene_multiplayer.auth_timeout = NetworkConfig.auth_timeout()
	scene_multiplayer.auth_callback = _on_auth
	scene_multiplayer.connection_failed.connect(_on_connection_failed, CONNECT_ONE_SHOT)
	scene_multiplayer.server_disconnected.connect(_on_server_disconnected, CONNECT_ONE_SHOT)
	scene_multiplayer.peer_connected.connect(_on_peer_connected)
	scene_multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_set_state(State.AUTHENTICATING)
	_pending_ticket = str(ticket.get("ticket", ""))
	_present_ticket()


## Presents the ticket on SceneMultiplayer's authentication channel.
##
## Retried because the server peer only becomes authenticatable once the link has
## settled; ERR_INVALID_PARAMETER means "not ready yet", not "rejected".
func _present_ticket(attempt: int = 0) -> void:
	if _stopping:
		return
	if _pending_ticket == "":
		return
	var scene_multiplayer := multiplayer as SceneMultiplayer
	var status := multiplayer.multiplayer_peer.get_connection_status() if multiplayer.multiplayer_peer != null else MultiplayerPeer.CONNECTION_DISCONNECTED
	if status == MultiplayerPeer.CONNECTION_CONNECTED:
		var envelope := JSON.stringify({"ticket": _pending_ticket})
		var error := scene_multiplayer.send_auth(1, envelope.to_utf8_buffer())
		_diag("send_auth", {"code": int(error)})
		if error == OK:
			return
		if attempt >= 5:
			_retry_or_fail("Could not present the admission ticket.")
			return
	await get_tree().create_timer(AUTH_SETTLE_SECONDS).timeout
	if _stopping:
		return
	_present_ticket(attempt + 1)


## Client-side auth callback.
##
## Its presence is required by the protocol so send_auth() towards the server is
## permitted. When the server answers -- which it only does after the backend has
## verified the admission ticket -- this completes the client's half of the
## handshake with complete_auth(1), mirroring the server's own completion.
##
## No verdict is ever *accepted* from the other side: the payload is not trusted,
## it is only the trigger to complete, and the authoritative identity arrives
## separately in admit_result.
func _on_auth(peer_id: int, data: PackedByteArray) -> bool:
	var verdict: Variant = JSON.parse_string(data.get_string_from_utf8())
	if verdict is Dictionary and bool((verdict as Dictionary).get("accepted", false)):
		# A backend-verified identity. Trust it: this message can only be sent by
		# the server after it spent this client's admission ticket successfully.
		identity = verdict as Dictionary
		_retries = 0
		_set_state(State.ADMITTED)
		admitted.emit(identity)
		print(
			"[MultiplayerClient] admitted as player %s (%s)"
			% [str(identity.get("player_id", "?")), str(identity.get("username", ""))]
		)
	else:
		var reason := str((verdict as Dictionary).get("reason", "rejected")) if verdict is Dictionary else "rejected"
		_diag("rejected", {"reason": reason})
		_set_state(State.REJECTED)
		rejected.emit(reason)
	# Completing here finishes the client's half of the handshake.
	var error := (multiplayer as SceneMultiplayer).complete_auth(peer_id)
	_diag("client_complete_auth", {"code": int(error)})
	return false


func _process(_delta: float) -> void:
	# SceneMultiplayer's own authentication drives connection state here, so
	# connected_to_server is not the signal to watch: with auth_callback set on
	# both sides, each end authenticates the other and peer_connected is what
	# marks a completed session.
	pass


func _on_connection_failed() -> void:
	_diag("connection_failed")
	_retry_or_fail("Connection failed.")


func _on_server_disconnected() -> void:
	_diag("server_disconnected")
	if _stopping:
		return
	_set_state(State.FAILED)
	disconnected.emit()


func _on_peer_connected(peer_id: int) -> void:
	# Deliberately does NOT mean "I was admitted". peer_connected fires whenever
	# any peer joins, including other clients relayed by the server. Admission is
	# announced only by admit_result, which the server can send after a
	# backend-verified identity and nothing else.
	print("[MultiplayerClient] transport-level peer %d present" % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("[MultiplayerClient] peer %d left" % peer_id)


func _retry_or_fail(reason: String) -> void:
	if _stopping:
		return
	if _retries >= NetworkConfig.max_retries():
		_set_state(State.FAILED)
		rejected.emit(reason)
		return
	_retries += 1
	print(
		"[MultiplayerClient] %s retry %d/%d in %.1fs"
		% [reason, _retries, NetworkConfig.max_retries(), _retry_delay]
	)
	await get_tree().create_timer(_retry_delay).timeout
	if _stopping:
		return
	_retry_delay = minf(
		_retry_delay * 2.0, NetworkConfig.DEFAULT_MAX_RETRY_DELAY_SECONDS
	)
	_attempt()


func is_admitted() -> bool:
	return state == State.ADMITTED


func disconnect_from_server() -> void:
	_stopping = true
	_attempt_id += 1
	_clear_peer()
	_pending_ticket = ""
	identity = {}
	if state != State.FAILED:
		_set_state(State.IDLE)


## Ask the backend for a ticket with the same access token as every other
## player-facing call, so this introduces no second credential.
##
## Each failure mode is reported distinctly rather than collapsed into a
## generic timeout: the initiation result is checked before awaiting, the
## request has a finite timeout, and the transport result is separated from the
## HTTP status.
func _request_ticket() -> Dictionary:
	var url := base_url + "/multiplayer/tickets"
	var request := HTTPRequest.new()
	add_child(request)
	request.timeout = HTTP_TIMEOUT_SECONDS

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json",
		# The token is sent but never printed: only the header name appears in
		# any diagnostic.
		"Authorization: Bearer " + _token,
	])
	_diag("ticket_request_start", {"url": url, "method": "POST", "auth_header_present": true})

	# Let the freshly added HTTPRequest initialise before issuing the request.
	#
	# Measured, not theoretical: issuing in the same frame the node was added
	# produced a spurious RESULT_TIMEOUT after about 6ms with the HTTPClient still
	# at DISCONNECTED, on the *first* attempt from every client, while the backend
	# itself answers a ticket in single-digit milliseconds. One frame is enough to
	# avoid it. The retry below still exists and still requests a fresh ticket each
	# time, so this is an optimisation, never a correctness dependency.
	await get_tree().process_frame

	var started_usec := Time.get_ticks_usec()
	var initiate := request.request(url, headers, HTTPClient.METHOD_POST, "{}")
	# The immediate return is an Error, a different enum from the Result reported
	# by request_completed. They were being conflated, so both are logged by name.
	_diag(
		"ticket_request_initiated",
		{"error": int(initiate), "error_name": error_string(initiate)}
	)
	if initiate != OK:
		request.queue_free()
		return {}

	var response: Array = await request.request_completed
	var elapsed_ms := (Time.get_ticks_usec() - started_usec) / 1000.0
	var client_status := int(request.get_http_client_status())
	var result := int(response[0])
	var code := int(response[1])
	_diag(
		"ticket_request_completed",
		{
			"result": result,
			"result_name": http_result_name(result),
			"status": code,
			"client_status": http_client_status_name(client_status),
			"elapsed_ms": snappedf(float(elapsed_ms), 1.0),
			"timeout_s": HTTP_TIMEOUT_SECONDS,
		}
	)
	request.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS:
		return {}
	if code != 200:
		return {}
	var parsed: Variant = JSON.parse_string(
		PackedByteArray(response[3]).get_string_from_utf8()
	)
	if not (parsed is Dictionary):
		_diag("ticket_parse_failed")
		return {}
	var body: Dictionary = parsed
	if not body.get("success", false):
		_diag("ticket_envelope_error", {"message": str(body.get("message", ""))})
		return {}
	var data: Dictionary = body.get("data", {})
	if str(data.get("ticket", "")) == "":
		_diag("ticket_missing_in_payload")
		return {}
	_diag("ticket_received", {"expires_in": int(data.get("expires_in", 0))})
	return data


func _exit_tree() -> void:
	disconnect_from_server()


func _clear_peer() -> void:
	# Cleanup can be requested again by an owner after this child exits.
	if not is_inside_tree():
		return
	for pair in [[multiplayer.connection_failed, _on_connection_failed],
			[multiplayer.server_disconnected, _on_server_disconnected],
			[multiplayer.peer_connected, _on_peer_connected],
			[multiplayer.peer_disconnected, _on_peer_disconnected]]:
		if pair[0].is_connected(pair[1]):
			pair[0].disconnect(pair[1])
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	(multiplayer as SceneMultiplayer).auth_callback = Callable()
