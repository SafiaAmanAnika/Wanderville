extends Node

signal connection_changed(connected: bool)
signal snapshot_received(snapshot: Dictionary)
signal nearby_message_received(message: Dictionary)
signal direct_message_received(message: Dictionary)
signal conversation_polled(target_id: int)
signal request_failed(message: String)
signal visit_ended(message: String)
signal room_changed(room: String)

var connected := false
var players: Array = []
var pause_movement := false   # NEW: true while inside a house — don't send or correct our position
var _socket: WebSocketPeer
var _auth_sent := false
var _sequence := 0
var _pending_sequence := 0
var _move_elapsed := 0.0
var _retry_elapsed := 0.0
var _connection_elapsed := 0.0
var _last_packet_elapsed := 0.0
var _correct_position := true
var _refreshing := false
var _seen_messages: Dictionary = {}
var _watched_conversations: Dictionary = {}
var _chat_elapsed := 0.0
var _chat_polling := false
var _owner := 0
var _version := -1
var _retry_delay := 1.0
var _conversation_versions: Dictionary = {}
var _room := ""
# The world this client wants to be standing in. Zero means the shared campus;
# otherwise it is the id of the world to enter, which the server re-derives
# permission for. It is a request, never a claim: the server answers with the
# room it actually put us in.
var _wanted_owner_id := 0


func _enter_payload() -> Dictionary:
	# The campus is requested by omission: the server treats a missing owner_id
	# as "no farm", and a literal 0 would fail validation.
	return {} if _wanted_owner_id <= 0 else {"owner_id": _wanted_owner_id}


func enter_world(owner_id: int) -> void:
	# Switching rooms is a server-side decision: the socket has to re-enter with
	# the world the player just resolved, and only an accepted invitation or
	# ownership will be honoured.
	if _wanted_owner_id == owner_id:
		return
	_wanted_owner_id = owner_id
	_correct_position = true
	_sequence = 0
	_pending_sequence = 0
	if connected:
		_send("enter", _enter_payload())


func restore_own_world() -> void:
	# Back to where every non-visiting player belongs: the shared campus. The
	# server has already closed the visit by the time this is called.
	enter_world(GameState.desired_world_id())


func _in_world() -> bool:
	var scene := get_tree().current_scene
	return Global.is_logged_in() and scene != null and scene.scene_file_path == SceneManager.WORLD_SCENE


func stop() -> void:
	if _socket != null:
		_socket.close()
	_socket = null
	_auth_sent = false
	_pending_sequence = 0
	_correct_position = true
	players.clear()
	_set_connected(false)
	snapshot_received.emit({"players": [], "messages": []})


func clear_session() -> void:
	stop()
	_watched_conversations.clear()
	_conversation_versions.clear()
	_seen_messages.clear()
	_version = Global.session_version
	_retry_delay = 1.0
	_retry_elapsed = 0.0
	_refreshing = false
	_chat_polling = false
	_owner = 0


func _set_connected(value: bool) -> void:
	if connected != value:
		connected = value
		connection_changed.emit(value)


func _connect_socket() -> void:
	_socket = WebSocketPeer.new()
	var url: String = APIClient.base_url.rstrip("/")
	url = url.replace("https://", "wss://").replace("http://", "ws://")
	_auth_sent = false
	_correct_position = true
	_connection_elapsed = 0.0
	_last_packet_elapsed = 0.0
	if _socket.connect_to_url(url + "/realtime/ws") != OK:
		_schedule_reconnect()


func _schedule_reconnect() -> void:
	stop()
	_retry_elapsed = _retry_delay + randf_range(0.0, 0.3)
	_retry_delay = minf(_retry_delay * 2.0, 15.0)


func _process(delta: float) -> void:
	if not _in_world():
		if _socket != null:
			stop()
		_watched_conversations.clear()
		return
	if _version != Global.session_version:
		clear_session()
		_owner = Global.player_id
	if _refreshing:
		return
	if _socket == null:
		_retry_elapsed -= delta
		if _retry_elapsed <= 0.0:
			_connect_socket()
		return
	_socket.poll()
	_connection_elapsed += delta
	_last_packet_elapsed += delta
	var state := _socket.get_ready_state()
	if state == WebSocketPeer.STATE_CLOSED or _last_packet_elapsed > 12.0:
		_schedule_reconnect()
		return
	if state != WebSocketPeer.STATE_OPEN:
		return
	if not _auth_sent:
		_socket.send_text(JSON.stringify({"type": "auth", "token": Global.token}))
		_auth_sent = true
		# The server opens the socket in the campus room by default. If this
		# player belongs somewhere else right now, ask for it explicitly before
		# the first frame is applied, so we never render the wrong world.
		if _wanted_owner_id > 0:
			_send("enter", _enter_payload())
	while _socket != null and _socket.get_available_packet_count() > 0:
		var packet: Variant = JSON.parse_string(_socket.get_packet().get_string_from_utf8())
		_last_packet_elapsed = 0.0
		if packet is Dictionary:
			_handle_packet(packet)
	if not connected:
		return
	_move_elapsed += delta
	if _move_elapsed >= 0.2 and _pending_sequence == 0 and not pause_movement:
		_move_elapsed = 0.0
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player != null:
			_sequence += 1
			_pending_sequence = _sequence
			_send("move", {"x": player.global_position.x, "y": player.global_position.y, "sequence": _sequence})
	_chat_elapsed += delta
	if _chat_elapsed >= 2.0 and not _chat_polling:
		_chat_elapsed = 0.0
		_poll_direct_messages()


func _handle_packet(packet: Dictionary) -> void:
	if packet.get("type") == "error":
		var code := str(packet.get("error", ""))
		if code == "VISIT_ENDED":
			# The host kicked us, went offline, or the slot was swept. The campus
			# is where every non-visiting player belongs, so that is where this
			# puts us rather than a room whose permission may already be gone.
			_wanted_owner_id = 0
			_correct_position = true
			_sequence = 0
			_pending_sequence = 0
			visit_ended.emit(str(packet.get("message", "Your visit has ended.")))
			_send("enter", _enter_payload())
			return
		request_failed.emit(str(packet.get("message", "Realtime request failed")))
		if int(packet.get("status", 0)) == 401:
			_reauthenticate()
		elif int(packet.get("status", 0)) == 403:
			# The server refused the world we asked for, which happens when a
			# visitor names a world that is not the one hosting them. The campus
			# is the one room always open to everybody, so fall back there rather
			# than trusting a local session that may already be stale.
			if _wanted_owner_id != 0:
				enter_world(0)
			else:
				_pending_sequence = 0
				_correct_position = true
		elif code == "SESSION_EXPIRED":
			_schedule_reconnect()
		else:
			_pending_sequence = 0
			_correct_position = true
			_send("snapshot", {})
		return
	if packet.get("type") != "snapshot" or not packet.get("data") is Dictionary:
		return
	var data: Dictionary = packet["data"]
	players = data.get("players", [])
	var room := str(data.get("room", _room))
	if room != _room:
		_room = room
		room_changed.emit(_room)
	if data.get("session") is Dictionary:
		GameState.apply_session(data["session"])
	for entry in players:
		if int(entry.get("player_id", 0)) == Global.player_id:
			var accepted := int(entry.get("sequence", 0))
			_sequence = maxi(_sequence, accepted)
			if accepted >= _pending_sequence:
				_pending_sequence = 0
			if _correct_position and not pause_movement:
				var player := get_tree().get_first_node_in_group("player") as Node2D
				if player != null:
					player.global_position = Vector2(float(entry["x"]), float(entry["y"]))
					_sequence = accepted
					_correct_position = false
					_retry_delay = 1.0
					_set_connected(true)
	for message in data.get("messages", []):
		var id := int(message.get("id", 0))
		if not _seen_messages.has(id):
			_seen_messages[id] = true
			nearby_message_received.emit(message)
	while _seen_messages.size() > 512:
		_seen_messages.erase(_seen_messages.keys()[0])
	snapshot_received.emit(data)


func _reauthenticate() -> void:
	if _refreshing:
		return
	_refreshing = true
	var version := Global.session_version
	stop()
	var success: bool = await APIClient.refresh_session()
	if version != Global.session_version:
		return
	_refreshing = false
	_retry_elapsed = 0.0 if success else 10.0
	if not success:
		APIClient.session_expired.emit()


func _send(kind: String, data: Dictionary) -> bool:
	if _socket == null or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	return _socket.send_text(JSON.stringify({"type": kind, "data": data})) == OK


func send_nearby_chat(message: String) -> bool:
	return connected and _send("chat", {"body": message})


func send_emote(emote: String) -> bool:
	return connected and _send("emote", {"emote": emote})


func watch_conversation(target_id: int, after: int = 0) -> void:
	_conversation_versions[target_id] = int(_conversation_versions.get(target_id, 0)) + 1
	_watched_conversations[target_id] = after


func unwatch_conversation(target_id: int) -> void:
	_conversation_versions[target_id] = int(_conversation_versions.get(target_id, 0)) + 1
	_watched_conversations.erase(target_id)


func _poll_direct_messages() -> void:
	_chat_polling = true
	var version := Global.session_version
	for target in _watched_conversations.keys():
		var conversation_version := int(_conversation_versions.get(target, 0))
		var response: Dictionary = await APIClient.get_direct_messages(target, int(_watched_conversations.get(target, 0)))
		if version != Global.session_version:
			return
		if not _watched_conversations.has(target) or conversation_version != int(_conversation_versions.get(target, 0)) or not _in_world():
			continue
		var messages: Variant = APIClient.data_of(response)
		if bool(response.get("ok", false)) and messages is Array:
			for message in messages:
				_watched_conversations[target] = maxi(int(_watched_conversations[target]), int(message["id"]))
				direct_message_received.emit(message)
			conversation_polled.emit(target)
		else:
			request_failed.emit(APIClient.error_text(response))
			if int(response.get("status_code", 0)) in [403, 404]:
				unwatch_conversation(target)
	_chat_polling = false
