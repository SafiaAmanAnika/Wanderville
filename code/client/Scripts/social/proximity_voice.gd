extends Node
## Native Godot voice. No browser or JavaScript runtime is required.
## One 20 ms mono PCM16 frame per binary WebSocket packet at 48 kHz.
##
## The server may send Opus instead of raw PCM, which is about thirty times
## less audio on the wire. The client asks for it only when a native decoder
## is actually present, so a build without the decoder keeps using raw PCM.
signal status_changed(text: String)
signal changed

## Seconds without any message from the voice server before the session is
## treated as dead.
##
## Deliberately long. The server stops sending frames of silence, so a quiet
## room is silent on the wire; the server sends a small keepalive instead, and
## this window has to tolerate a few of those being late. A closed socket is
## still noticed immediately, because that is the common failure.
const SIGNAL_TIMEOUT := 15.0

## How fast the level meter falls back to silence, in meters per second.
const LEVEL_DECAY := 4.0

## The class the native Opus decoder registers as. The extension is
## optional: when it is missing, the client never asks for Opus.
const OPUS_DECODER_CLASS := "OpusDecoder"

## The marker that opens a compressed audio packet. Raw PCM is sent as
## 1,920 bytes with no header at all, so the two can never be confused.
const OPUS_MARKER := 1

## One audio frame is 20 ms.
const FRAME_SECONDS := 0.02
const FRAME_BYTES := 1920

## How many frames the jitter buffer gathers before it starts playing out,
## and the most it will ever hold. The first number is the jitter it can
## absorb, the second is the delay it will never exceed: a frame that
## arrives after the buffer is full is dropped rather than played late.
const JITTER_TARGET_FRAMES := 3
const JITTER_MAX_FRAMES := 10

var session_id := ""
var output_level := 0.0
var muted := true
var deafened := false
var muted_players: Array[int] = []
## Audio frames received since the session started. Public because the
## integration test reads it to prove a quiet room sends nothing.
var frames_received := 0
## Keepalives received since the session started. The server sends one while
## the room is quiet, so this is the client's proof that the session lives.
var keepalives_received := 0
## Compressed frames the jitter buffer had to throw away because they
## arrived too late to be played.
var frames_dropped := 0
## Compressed frames that could not be decoded at all.
var frames_failed := 0
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
## Seconds since the last message of any kind. Silence is not a dead
## connection, so this counts every message, not only audio frames.
var _last_signal := 0.0
## The encoding the server said it is using: "pcm_s16le" or "opus".
var _encoding := "pcm_s16le"
## The native Opus decoder, when the extension is present.
var _opus_decoder: Object = null
## Decoded audio waiting to be played, one entry per 20 ms frame.
var _jitter: Array[PackedByteArray] = []
## Decoded audio that has not filled a whole frame yet.
var _pcm_pending := PackedByteArray()
## Seconds until the next frame is played out.
var _jitter_clock := 0.0
## Whether the jitter buffer has gathered enough to start playing.
var _jitter_started := false


func _ready() -> void:
	APIClient.realtime.connection_changed.connect(func(connected: bool) -> void:
		if not connected:
			leave(false)
	)
	APIClient.realtime.voice_updated.connect(_server_state)
	APIClient.realtime.room_changed.connect(func(_room: String) -> void: leave(false))
	_speaker = AudioStreamPlayer.new()
	add_child(_speaker)
	_load_opus_decoder()


## The native decoder is optional, so its absence is not an error: the client
## simply never asks for Opus and the server keeps sending raw PCM.
func _load_opus_decoder() -> void:
	if not ClassDB.class_exists(OPUS_DECODER_CLASS):
		return
	_opus_decoder = ClassDB.instantiate(OPUS_DECODER_CLASS)
	if _opus_decoder == null:
		_opus_decoder = null


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
	_last_signal = 0.0
	frames_received = 0
	keepalives_received = 0
	frames_dropped = 0
	frames_failed = 0
	_encoding = "pcm_s16le"
	_jitter.clear()
	_pcm_pending = PackedByteArray()
	_jitter_clock = 0.0
	_jitter_started = false
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
	_last_signal += delta
	# The meter falls on its own. A suppressed frame means the room is quiet,
	# and the indicator must not stay stuck at the level of the last word that
	# was spoken.
	output_level = maxf(0.0, output_level - delta * LEVEL_DECAY)
	if _ready_audio:
		_pump_jitter(delta)
	if (
		_socket.get_ready_state() == WebSocketPeer.STATE_CLOSED
		or (_elapsed > 5 and not _ready_audio)
		or (_ready_audio and _last_signal > SIGNAL_TIMEOUT)
	):
		leave()
		status_changed.emit("Voice disconnected. Join again.")
		return
	if _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	if not _authenticated:
		# "silence_suppression" says this client can live without frames of
		# silence: the server will send nothing at all while the room is quiet
		# and keep the session alive with a small keepalive instead. A server
		# that does not know the capability still sends frames, and this client
		# still reads them, so the two ends work either way.
		#
		# "opus" is only claimed when a decoder is really there. Claiming it
		# without one would leave the client unable to hear anything.
		var capabilities := ["silence_suppression"]
		if _opus_decoder != null:
			capabilities.append("opus")
		_socket.send_text(
			JSON.stringify(
				{
					"type": "auth",
					"token": Global.token,
					"connection_id": APIClient.realtime.connection_id,
					"session_id": session_id,
					"capabilities": capabilities,
				}
			)
		)
		_authenticated = true
	while _socket.get_available_packet_count() > 0:
		var bytes := _socket.get_packet()
		# Any message proves the session is alive, including the keepalive the
		# server sends into a quiet room.
		_last_signal = 0.0
		if _socket.was_string_packet():
			var packet: Variant = JSON.parse_string(bytes.get_string_from_utf8())
			if packet is Dictionary:
				if packet.get("type") == "voice.connected":
					_ready_audio = true
					_start_playback()
					status_changed.emit("Listening. Hold Talk to use your microphone (headphones recommended).")
					changed.emit()
				elif packet.get("type") == "voice.idle":
					# The server says the room is quiet. It is also the proof
					# that the session is still alive.
					keepalives_received += 1
				elif packet.get("type") == "voice.format":
					_encoding = str(packet.get("encoding", "pcm_s16le"))
					if _encoding == "opus" and _opus_decoder == null:
						# The server is sending audio this client cannot
						# decode. The only honest answer is to end the session
						# and start again without asking for Opus, so the two
						# ends agree on raw PCM.
						status_changed.emit("Voice encoding mismatch. Reconnecting.")
						leave()
						join_voice()
						return
		elif _ready_audio:
			if _encoding == "opus":
				_receive_opus(bytes)
			elif bytes.size() == FRAME_BYTES:
				_receive_pcm(bytes)
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


## Raw PCM, the way the client has always received it.
##
## The generator's own buffer smooths the arrival of these frames, so they
## are played as they come.
func _receive_pcm(bytes: PackedByteArray) -> void:
	frames_received += 1
	_measure_level(bytes)
	if deafened or _playback == null:
		return
	if _playback.get_frames_available() < 960:
		return
	_playback.push_buffer(_to_samples(bytes))


## One compressed frame: decode it and hand the audio to the jitter buffer.
func _receive_opus(bytes: PackedByteArray) -> void:
	if bytes.size() < 2 or bytes[0] != OPUS_MARKER:
		# Not a compressed frame. The server states the encoding before any
		# audio arrives, so this means the two ends disagree.
		frames_failed += 1
		return
	frames_received += 1
	var pcm: PackedByteArray = _opus_decoder.decode(bytes.slice(1))
	if pcm.is_empty():
		# A frame that arrived damaged is dropped, not played as noise.
		frames_failed += 1
		return
	_pcm_pending.append_array(pcm)
	while _pcm_pending.size() >= FRAME_BYTES:
		_jitter.append(_pcm_pending.slice(0, FRAME_BYTES))
		_pcm_pending = _pcm_pending.slice(FRAME_BYTES)
	_measure_level(pcm)


## Play the decoded audio out at a steady rate.
##
## The buffer gathers a few frames before it starts, so the jitter of the
## network is absorbed instead of turning into gaps in the speech, and it
## never holds more than a fixed number of frames, so the delay cannot grow
## without bound. A frame that arrives after the buffer is full is stale and
## is dropped.
func _pump_jitter(delta: float) -> void:
	_jitter_clock += delta
	while _jitter_clock >= FRAME_SECONDS:
		_jitter_clock -= FRAME_SECONDS
		if _jitter.size() > JITTER_MAX_FRAMES:
			_jitter.pop_front()
			frames_dropped += 1
		if not _jitter_started:
			if _jitter.size() < JITTER_TARGET_FRAMES:
				continue
			_jitter_started = true
		if _jitter.is_empty():
			# The stream has started but nothing arrived in time. Silence
			# keeps the speaker from clicking while the buffer refills.
			if not deafened and _playback != null and _playback.get_frames_available() >= 960:
				_playback.push_buffer(_silence())
			continue
		var frame: PackedByteArray = _jitter.pop_front()
		if not deafened and _playback != null and _playback.get_frames_available() >= 960:
			_playback.push_buffer(_to_samples(frame))


## The loudest sample in a frame, for the level meter.
func _measure_level(bytes: PackedByteArray) -> void:
	output_level = 0.0
	var count := bytes.size() / 2
	for i in count:
		output_level = maxf(output_level, absf(float(bytes.decode_s16(i * 2)) / 32768.0))


## PCM16 bytes to the samples the generator plays.
func _to_samples(bytes: PackedByteArray) -> PackedVector2Array:
	var count := bytes.size() / 2
	var frames := PackedVector2Array()
	frames.resize(count)
	for i in count:
		var sample := float(bytes.decode_s16(i * 2)) / 32768.0
		frames[i] = Vector2(sample, sample)
	return frames


## One frame of silence, to fill a gap without a click.
func _silence() -> PackedVector2Array:
	var frames := PackedVector2Array()
	frames.resize(960)
	frames.fill(Vector2.ZERO)
	return frames


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
	_last_signal = 0.0
	_encoding = "pcm_s16le"
	_jitter.clear()
	_pcm_pending = PackedByteArray()
	_jitter_clock = 0.0
	_jitter_started = false
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
