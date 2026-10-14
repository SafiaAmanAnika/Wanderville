extends Node
## Native Godot voice. No browser or JavaScript runtime is required.
## One 20 ms mono PCM16 frame per binary WebSocket packet at 48 kHz.
signal status_changed(text: String)
signal changed

var session_id := ""
var output_level := 0.0
var muted := true
var deafened := false
var muted_players: Array[int] = []
var _socket: WebSocketPeer
var _authenticated := false
var _ready_audio := false
var _joining := false
var _talk_version := 0
var _capture: AudioEffectCapture
var _microphone: AudioStreamPlayer
var _speaker: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _bus := -1
var _elapsed := 0.0
var _last_audio := 0.0


func _ready() -> void:
	APIClient.realtime.connection_changed.connect(func(connected: bool) -> void:
		if not connected:
			leave(false)
	)
	APIClient.realtime.voice_updated.connect(_server_state)
	APIClient.realtime.room_changed.connect(func(_room: String) -> void: leave(false))
	_speaker = AudioStreamPlayer.new()
	add_child(_speaker)


func join_voice() -> void:
	if _joining or not session_id.is_empty():
		return
	_joining = true
	status_changed.emit("Joining voice, microphone off...")
	var result: Dictionary = await APIClient.realtime.command("voice.join", {"transport": "pcm-websocket"})
	_joining = false
	if not result.get("ok", false):
		status_changed.emit(str(result.get("message", "Voice unavailable")))
		return
	session_id = str(result["data"]["session_id"])
	muted = true
	deafened = false
	_socket = WebSocketPeer.new()
	_socket.inbound_buffer_size = 32768
	_socket.outbound_buffer_size = 8192
	_socket.max_queued_packets = 8
	var url: String = APIClient.base_url.rstrip("/").replace("https://", "wss://").replace("http://", "ws://")
	if _socket.connect_to_url(url + "/realtime/voice/ws") != OK:
		leave()
		status_changed.emit("Audio connection failed. Join again.")
		return
	_elapsed = 0.0
	_last_audio = 0.0
	changed.emit()


func _server_state(data: Dictionary) -> void:
	if not session_id.is_empty() and str(data.get("session_id", "")) != session_id:
		leave(false)
		status_changed.emit("Voice ended. Join again when ready.")


func _process(delta: float) -> void:
	if _socket == null:
		return
	_socket.poll()
	_elapsed += delta
	_last_audio += delta
	if _socket.get_ready_state() == WebSocketPeer.STATE_CLOSED or (_elapsed > 5 and not _ready_audio) or (_ready_audio and _last_audio > 2):
		leave()
		status_changed.emit("Voice disconnected. Join again.")
		return
	if _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	if not _authenticated:
		_socket.send_text(JSON.stringify({"type": "auth", "token": Global.token, "connection_id": APIClient.realtime.connection_id, "session_id": session_id}))
		_authenticated = true
	while _socket.get_available_packet_count() > 0:
		var bytes := _socket.get_packet()
		if _socket.was_string_packet():
			var packet: Variant = JSON.parse_string(bytes.get_string_from_utf8())
			if packet is Dictionary and packet.get("type") == "voice.connected":
				_ready_audio = true
				_start_playback()
				status_changed.emit("Listening. Hold Talk to use your microphone (headphones recommended).")
				changed.emit()
		elif bytes.size() == 1920 and _ready_audio:
			_last_audio = 0.0
			output_level = 0.0
			for i in 960:
				output_level = maxf(output_level, absf(float(bytes.decode_s16(i * 2)) / 32768.0))
			if not deafened and _playback != null and _playback.get_frames_available() >= 960:
				var frames := PackedVector2Array()
				frames.resize(960)
				for i in 960:
					var sample := float(bytes.decode_s16(i * 2)) / 32768.0
					frames[i] = Vector2(sample, sample)
				_playback.push_buffer(frames)
	if _capture == null or muted or deafened or not _ready_audio:
		return
	var input_count := int(round(AudioServer.get_mix_rate() * 0.02))
	# Drop stale capture rather than transmitting a delayed burst.
	if _capture.get_frames_available() > input_count * 3:
		_capture.clear_buffer()
	var sent := 0
	while _capture.can_get_buffer(input_count) and sent < 3:
		var samples := _capture.get_buffer(input_count)
		var bytes := PackedByteArray()
		bytes.resize(1920)
		for i in 960:
			var position := float(i) * float(input_count) / 960.0
			var index := int(position)
			var sample := samples[index].lerp(samples[mini(index + 1, input_count - 1)], position - index)
			bytes.encode_s16(i * 2, clampi(int((sample.x + sample.y) * 16383.5), -32768, 32767))
		if _socket.get_current_outbound_buffered_amount() > 3840:
			leave()
			status_changed.emit("Voice network too slow. Join again.")
			return
		_socket.send(bytes)
		sent += 1


func _start_playback() -> void:
	_speaker.volume_db = -80.0 if deafened else 0.0
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = 48000
	stream.buffer_length = 0.08
	_speaker.stream = stream
	_speaker.play()
	_playback = _speaker.get_stream_playback() as AudioStreamGeneratorPlayback


func talk(pressed: bool) -> void:
	_talk_version += 1
	var version := _talk_version
	_stop_capture()
	muted = true
	if session_id.is_empty() or not _ready_audio:
		return
	var requested_mute := not pressed or deafened
	var result: Dictionary = await APIClient.realtime.command("voice.state", {"session_id": session_id, "muted": requested_mute, "deafened": deafened, "muted_players": muted_players})
	if version != _talk_version or session_id.is_empty():
		return
	if not result.get("ok", false):
		status_changed.emit(str(result.get("message", "Could not update microphone")))
		return
	muted = requested_mute
	if not muted:
		_start_capture()
	changed.emit()


func _start_capture() -> void:
	if not ProjectSettings.get_setting("audio/driver/enable_input", false):
		status_changed.emit("Enable microphone input in Godot project settings.")
		talk(false)
		return
	if OS.has_feature("android") and not OS.get_granted_permissions().has("android.permission.RECORD_AUDIO"):
		OS.request_permission("android.permission.RECORD_AUDIO")
		status_changed.emit("Grant microphone permission, then hold Talk again.")
		talk(false)
		return
	AudioServer.add_bus()
	_bus = AudioServer.bus_count - 1
	AudioServer.set_bus_name(_bus, "ProximityMicrophone")
	AudioServer.set_bus_mute(_bus, true)
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 0.08
	AudioServer.add_bus_effect(_bus, _capture)
	_microphone = AudioStreamPlayer.new()
	_microphone.stream = AudioStreamMicrophone.new()
	_microphone.bus = "ProximityMicrophone"
	add_child(_microphone)
	_microphone.play()


func _stop_capture() -> void:
	if is_instance_valid(_microphone):
		_microphone.stop()
		_microphone.queue_free()
	_microphone = null
	_capture = null
	if _bus >= 0:
		AudioServer.remove_bus(_bus)
		_bus = -1


func set_deafened(value: bool) -> void:
	deafened = value
	_speaker.volume_db = -80.0 if value else 0.0
	if _playback != null:
		_playback.clear_buffer()
	talk(false)
	changed.emit()


func mute_player(player_id: int, value: bool) -> void:
	muted_players.erase(player_id)
	if value:
		muted_players.append(player_id)
	talk(false)


func leave(notify_server := true) -> void:
	_talk_version += 1
	_stop_capture()
	if is_instance_valid(_speaker):
		_speaker.stop()
	_playback = null
	if _socket != null:
		_socket.close()
	_socket = null
	_authenticated = false
	_ready_audio = false
	muted = true
	if not session_id.is_empty() and notify_server:
		APIClient.realtime.command("voice.leave")
	session_id = ""
	deafened = false
	output_level = 0.0
	muted_players.clear()
	status_changed.emit("Voice off. Join when you are ready.")
	changed.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		talk(false)


func _exit_tree() -> void:
	leave()
