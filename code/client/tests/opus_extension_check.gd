extends SceneTree
## Checks the native Opus decoder: that the extension loads, that it decodes
## a real Opus stream back into the same audio the server's own decoder
## produces, and that a frame no decoder can make sense of is refused rather
## than played as noise.
##
## The data lives in tests/opus_data. It was produced by the server's own
## encoder and decoded by the server's own decoder, so the two ends of the
## voice path are compared against each other.
##
##   godot --headless --path code/client --script res://tests/opus_extension_check.gd
##
## A folder can be given instead, to check a stream that is not the one in
## the repository.

var _failures := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var folder := "res://tests/opus_data"
	if args.size() >= 1:
		folder = args[0]
	_check(ClassDB.class_exists("OpusDecoder"), "decoder_class_registered")
	if _failures > 0:
		quit(1)
		return
	var decoder = ClassDB.instantiate("OpusDecoder")
	_check(decoder != null, "decoder_instantiated")
	if decoder == null:
		quit(1)
		return

	var stream := _read(folder.path_join("frames.opus"))
	var reference := _read(folder.path_join("reference.pcm"))
	var frame_size := int(_read_text(folder.path_join("frame_size.txt")))
	_check(stream.size() > 0 and frame_size > 0, "test_data_read")
	_check(stream.size() % frame_size == 0, "test_data_whole_frames")
	# The decoder keeps the state of the stream, so the frames are handed
	# over one by one, exactly as they arrive over the socket.
	var decoded := PackedByteArray()
	var count := stream.size() / frame_size
	for i in count:
		var piece: PackedByteArray = decoder.decode(stream.slice(i * frame_size, (i + 1) * frame_size))
		decoded.append_array(piece)
	_check(decoded.size() == reference.size(), "decoded_frame_size")
	if args.size() > 1:
		var out := FileAccess.open(args[1], FileAccess.WRITE)
		if out != null:
			out.store_buffer(decoded)
	var peak := _peak(decoded)
	var reference_peak := _peak(reference)
	_check(peak > 0.8 * reference_peak and peak < 1.25 * reference_peak, "decoded_level_matches")
	var match := _correlation(decoded, reference)
	print("OPUS_CHECK correlation: ", match)
	_check(match > 0.98, "decoded_audio_matches")

	var damaged := _read(folder.path_join("bad.opus"))
	var refused: PackedByteArray = decoder.decode(damaged)
	var error := str(decoder.get_last_error())
	_check(refused.is_empty(), "damaged_frame_refused")
	_check(error != "", "damaged_frame_reported")
	print("OPUS_CHECK decoder error: ", error)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, name: String) -> void:
	if condition:
		print("OPUS_CHECK ", name, " PASS")
	else:
		print("OPUS_CHECK ", name, " FAIL")
		_failures += 1


func _read(path: String) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	return file.get_buffer(file.get_length())


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text().strip_edges()


func _peak(bytes: PackedByteArray) -> float:
	var peak := 0.0
	var count := bytes.size() / 2
	for i in count:
		peak = maxf(peak, absf(float(bytes.decode_s16(i * 2)) / 32768.0))
	return peak


## How close the decoded audio is to the audio the server's decoder produced.
func _correlation(decoded: PackedByteArray, reference: PackedByteArray) -> float:
	var count := mini(decoded.size(), reference.size()) / 2
	if count == 0:
		return 0.0
	var difference := 0.0
	var energy := 0.0
	for i in count:
		var a := float(decoded.decode_s16(i * 2))
		var b := float(reference.decode_s16(i * 2))
		difference += (a - b) * (a - b)
		energy += b * b
	if energy <= 0.0:
		return 0.0
	return 1.0 - sqrt(difference / energy)
