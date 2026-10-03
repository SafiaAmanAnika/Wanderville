extends Node

signal connection_changed(connected: bool)
signal snapshot_received(snapshot: Dictionary)
signal nearby_message_received(message: Dictionary)
signal direct_message_received(message: Dictionary)
signal request_failed(message: String)

var connected := false
var players: Array = []
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
	_seen_messages.clear()
	_set_connected(false)


func clear_session() -> void:
	stop()
	_watched_conversations.clear()
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
		stop()
		_retry_elapsed = 2.0


func _process(delta: float) -> void:
	if not _in_world():
		if _socket != null:
			stop()
		return
	if _owner != Global.player_id:
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
		stop()
		_retry_elapsed = 2.0
		return
	if state != WebSocketPeer.STATE_OPEN:
		return
	if not _auth_sent:
		_socket.send_text(JSON.stringify({"type": "auth", "token": Global.token}))
		_auth_sent = true
	while _socket != null and _socket.get_available_packet_count() > 0:
		var packet: Variant = JSON.parse_string(_socket.get_packet().get_string_from_utf8())
		_last_packet_elapsed = 0.0
		if packet is Dictionary:
			_handle_packet(packet)
	if not connected:
		return
	_move_elapsed += delta
	if _move_elapsed >= 0.2 and _pending_sequence == 0:
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
		request_failed.emit(str(packet.get("message", "Realtime request failed")))
		if int(packet.get("status", 0)) == 401:
			_reauthenticate()
		elif int(packet.get("status", 0)) == 403:
			stop()
			_retry_elapsed = 10.0
		elif packet.get("error") == "SESSION_EXPIRED":
			stop()
		else:
			_pending_sequence = 0
			_correct_position = true
			_send("snapshot", {})
		return
	if packet.get("type") != "snapshot" or not packet.get("data") is Dictionary:
		return
	var data: Dictionary = packet["data"]
	players = data.get("players", [])
	for entry in players:
		if int(entry.get("player_id", 0)) == Global.player_id:
			var accepted := int(entry.get("sequence", 0))
			_sequence = maxi(_sequence, accepted)
			if accepted >= _pending_sequence:
				_pending_sequence = 0
			if _correct_position:
				var player := get_tree().get_first_node_in_group("player") as Node2D
				if player != null:
					player.global_position = Vector2(float(entry["x"]), float(entry["y"]))
					_sequence = accepted
					_correct_position = false
					_set_connected(true)
	var active_ids: Dictionary = {}
	for message in data.get("messages", []):
		var id := int(message.get("id", 0))
		active_ids[id] = true
		if not _seen_messages.has(id):
			nearby_message_received.emit(message)
	_seen_messages = active_ids
	snapshot_received.emit(data)


func _reauthenticate() -> void:
	if _refreshing:
		return
	_refreshing = true
	stop()
	var success: bool = await APIClient.refresh_session()
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
	_watched_conversations[target_id] = after


func unwatch_conversation(target_id: int) -> void:
	_watched_conversations.erase(target_id)


func _poll_direct_messages() -> void:
	_chat_polling = true
	var owner := Global.player_id
	for target in _watched_conversations.keys():
		var response: Dictionary = await APIClient.get_direct_messages(target, int(_watched_conversations.get(target, 0)))
		if owner != Global.player_id:
			break
		if not _watched_conversations.has(target):
			continue
		var messages: Variant = APIClient.data_of(response)
		if bool(response.get("ok", false)) and messages is Array:
			for message in messages:
				_watched_conversations[target] = maxi(int(_watched_conversations[target]), int(message["id"]))
				direct_message_received.emit(message)
	_chat_polling = false
