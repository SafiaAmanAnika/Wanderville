extends Node2D
## A rendered Godot window that plays the real movement stack with real keyboard
## input, so the Phase 3 ENet path can be judged by eye rather than by log.
##
## Nothing is reinvented here. Admission is the same MultiplayerClient the game
## uses, the socket is the same NetworkLink, movement is the same MovementClient
## against the same server-authoritative MovementAuthority, remote players are the
## same RemoteAvatar, and the collision world is the same MovementArena the
## headless tests use. This script only supplies what a window needs and a
## script cannot: a camera, a heads-up readout, screenshots, and a bounded
## lifetime so a supervising process is never left hanging.
##
## It loads no production gameplay scene and touches no gameplay code, so the
## normal game is unaffected and there is still only ever one movement authority.
##
## Input is real: WASD and the arrow keys drive MovementClient's own
## ``_read_input``, which falls through to ``ui_*`` actions whenever
## ``scripted_input`` is zero, which it always is here.
##
## Environment:
##   TEST_API_URL          backend base url            (default http://127.0.0.1:8000)
##   TEST_TOKEN            the player's access token
##   TEST_USERNAME         label shown in the window title
##   TEST_HOST             multiplayer host             (default 127.0.0.1)
##   TEST_PORT             multiplayer udp port         (default 24567)
##   TEST_CHARACTER        character code               (default farmer_female)
##   TEST_SCREENSHOT_DIR   write a PNG per milestone into this directory
##   TEST_RUN_SECONDS      quit after this many seconds (0 = stay open for a human)
##   TEST_INPUT_SCRIPT     optional scripted drive, e.g. "right:1.5;up:1.0".
##                         Unset, which is the normal case, the window is driven
##                         entirely by real keys. When set, it feeds
##                         MovementClient.scripted_input so an unattended run can
##                         make this window walk without a human at the keyboard;
##                         the scripted path replaces the keys rather than adding
##                         to them, so it cannot mask a broken input read.
##   TEST_AUTO_START       0 to open the window without connecting

var client: MultiplayerClient
var link: NetworkLink
var movement: MovementClient

var username := ""
var host := NetworkConfig.DEFAULT_HOST
var port := NetworkConfig.DEFAULT_PORT
var _api_url := "http://127.0.0.1:8000"
var _token := ""

var _status: Label
var _roster: Label
var _remotes: Label
var _hint: Label
var _screenshot_dir := ""
var _shot_index := 0
var _elapsed := 0.0
var _run_seconds := 0.0
var _phase := "starting"
var _errors: Array = []
var _last_remote_ids: Array = []
var _script_steps: Array = []
var _script_index := 0
var _script_time := 0.0
var _script_settle_until := 0.0
var _player_id := 0
var _anim_seen: Dictionary = {}
var _anim_max_frame: Dictionary = {}
## Camera zoom; see _build_camera() for why the default of 1 is far too wide.
const CAMERA_ZOOM := 3.0


func _ready() -> void:
	_api_url = OS.get_environment("TEST_API_URL")
	_token = OS.get_environment("TEST_TOKEN")
	username = OS.get_environment("TEST_USERNAME")
	if username == "":
		username = "player"
	host = OS.get_environment("TEST_HOST")
	if host == "":
		host = NetworkConfig.DEFAULT_HOST
	port = int(OS.get_environment("TEST_PORT"))
	if port <= 0:
		port = NetworkConfig.DEFAULT_PORT
	_screenshot_dir = OS.get_environment("TEST_SCREENSHOT_DIR")
	_run_seconds = float(OS.get_environment("TEST_RUN_SECONDS"))

	# Direct child of the scene root: NetworkLink's relative RPC path depends on it.
	link = NetworkLink.new()
	link.name = "NetworkLink"
	add_child(link)
	link.roster_received.connect(_on_roster)

	movement = MovementClient.new()
	movement.name = "MovementClient"
	add_child(movement)
	movement.setup(link)
	# Identical to the server's world so local prediction collides the same way
	# and reconciliation has nothing to argue about.
	movement.build_collision_world(self)
	_parse_input_script()

	_build_camera()
	_build_ui()

	# The peer is not opened here: MultiplayerClient opens it as part of the real
	# admission flow, exactly as the normal game does. Creating one at this point
	# would mean a second socket and a second code path.
	client = MultiplayerClient.new()
	add_child(client)
	client.configure(_api_url, _token)
	client.admitted.connect(_on_admitted)
	client.rejected.connect(_on_rejected)
	client.disconnected.connect(_on_disconnected)

	print("[RenderedMovement] display=%s host=%s port=%d user=%s" % [
		DisplayServer.get_name(), host, port, username,
	])
	_set_window_title()

	if OS.get_environment("TEST_AUTO_START") == "0":
		_phase = "idle"
		return
	client.connect_to_server(host, port)


func _build_camera() -> void:
	var camera := Camera2D.new()
	camera.name = "Camera"
	# Follow the local player. Not a child of the avatar: the avatar is respawned
	# on reconnect, and a camera parented to a node that can be freed would leave
	# the window staring at nothing.
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	#
	# Zoom is the whole of the "two-pixel sprite" bug, and it lives here rather
	# than in RemoteAvatar because RemoteAvatar is not at fault.
	#
	# The character frames are 48x48 (girl.tscn) and the sprite inside them carries
	# scale 0.3, so a character is 48 * 0.3 = 14.4 world units tall. At the default
	# camera zoom of 1 that is 14 pixels -- a speck, with the name label towering
	# over it, which is exactly what the first screenshots showed. Godot maps one
	# world unit to one pixel at zoom 1, so the zoom has to undo the sprite's own
	# 0.3 to get the artwork back to its authored 48 pixels: 1 / 0.3 = 3.333.
	# 3.0 is used instead, a whole number that stays a little wider than native and
	# keeps both spawn-ring neighbours (260 units apart) comfortably in frame.
	#
	# This is a view setting on an isolated test scene. It touches no art, no
	# collision, and no coordinate: the server still moves the player 300 units a
	# second and the sprites are still the original textures at their original
	# scale.
	camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
	add_child(camera)
	camera.make_current()

	# Pixel art stays crisp only under nearest-neighbour filtering. The project
	# default is linear, which is right for the big painted campus tiles and wrong
	# for these sprites, and project.godot is not this scene's to change, so the
	# filter is set here and inherited by every child.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	_status = _label(layer, Vector2(16, 12), "connecting...")
	_status.add_theme_color_override("font_color", Color(1, 1, 1))
	_roster = _label(layer, Vector2(16, 40), "roster: -")
	_remotes = _label(layer, Vector2(16, 68), "remotes: -")
	_hint = _label(layer, Vector2(16, 96), "WASD / arrows to move")
	_hint.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	_label(layer, Vector2(16, 124), "F1 screenshot")


func _label(layer: CanvasLayer, at: Vector2, text: String) -> Label:
	var node := Label.new()
	node.position = at
	node.add_theme_font_size_override("font_size", 18)
	node.add_theme_color_override("font_color", Color(1, 1, 1))
	node.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	node.add_theme_constant_override("outline_size", 4)
	node.text = text
	layer.add_child(node)
	return node


func _set_window_title() -> void:
	DisplayServer.window_set_title("Wanderville rendered movement - %s" % username)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			_capture("manual")


func _process(delta: float) -> void:
	_elapsed += delta
	_drive_script(delta)
	_refresh_hud()

	if _run_seconds > 0.0 and _elapsed >= _run_seconds:
		_finish()


## Feeds MovementClient.scripted_input so an unattended run can walk this window.
## Deliberately mirrors the shape of MovementHarness's parser so the two agree on
## what "right:1.5" means.
func _parse_input_script() -> void:
	var raw := OS.get_environment("TEST_INPUT_SCRIPT")
	if raw == "":
		return
	for chunk in raw.split(";"):
		var part := chunk.strip_edges()
		if part == "":
			continue
		var bits := part.split(":")
		var seconds := 1.0
		if bits.size() > 1:
			seconds = float(bits[1])
		_script_steps.append({"dir": _direction(bits[0]), "seconds": seconds})


func _direction(word: String) -> Vector2:
	match word.strip_edges().to_lower():
		"left":
			return Vector2.LEFT
		"right":
			return Vector2.RIGHT
		"up":
			return Vector2.UP
		"down":
			return Vector2.DOWN
	return Vector2.ZERO


## Report a sprite's animation state whenever it changes.
##
## This exists because "the character animates" cannot be established from a
## screenshot, and should not be asserted from one. It is also not a substitute
## for looking at it: what it proves is that the sprite is being driven, that it
## changes when the player does, and that it stops when the player stops. Whether
## the result looks right is a question for a person.
func _trace_animation(scope: String, id: int, body: Node) -> void:
	if OS.get_environment("TEST_TRACE_ANIM") != "1" or body == null:
		return
	var sprite := CharacterPresentation.sprite_of(body)
	if sprite == null:
		return
	var moving := sprite.is_playing()

	# Track the furthest frame reached per animation. The transition log below only
	# fires when play state changes, and a freshly started animation is always on
	# frame 0, so the transitions alone cannot show that a walk cycle advanced.
	var fkey := "%s/%s" % [scope, sprite.animation]
	_anim_max_frame[fkey] = maxi(int(_anim_max_frame.get(fkey, 0)), sprite.frame)

	var key := "%s/%d/%s" % [scope, id, sprite.animation]
	if _anim_seen.get(key) == moving:
		return
	_anim_seen[key] = moving
	print("RESULT anim=1 scope=%s id=%d name=%s frame=%d playing=%s" % [
		scope, id, sprite.animation, sprite.frame, str(moving),
	])


func _drive_script(delta: float) -> void:
	if movement == null or _script_steps.is_empty():
		return
	if _script_index >= _script_steps.size():
		# Script finished: release the keys so the server's own input expiry is what
		# stops this player, rather than the client politely sending neutral.
		if movement.scripted_input != Vector2.ZERO:
			movement.scripted_input = Vector2.ZERO
		return
	if _script_settle_until > 0.0:
		if _elapsed >= _script_settle_until:
			movement.scripted_input = Vector2.ZERO
			_script_settle_until = 0.0
			_script_index += 1
		return
	_script_time += delta
	if _script_time < 0.5:
		return
	_script_time = 0.0
	var step: Dictionary = _script_steps[_script_index]
	movement.scripted_input = step["dir"]
	_script_settle_until = _elapsed + float(step["seconds"])


func _refresh_hud() -> void:
	if movement == null:
		return
	var cam := get_node_or_null("Camera") as Camera2D
	if cam != null:
		cam.global_position = movement.local_position()
	_status.text = "%s | %s | pos %.0f,%.0f | corrections %d" % [
		username, _phase, movement.local_position().x,
		movement.local_position().y, movement.correction_count(),
	]
	_trace_animation("local", _player_id, movement.local)
	var ids := movement.remote_ids()
	var parts: Array = []
	for id in ids:
		var avatar := movement.remote_avatar(id)
		if avatar == null:
			continue
		# Deliberately the avatar's name and not its global_position: RemoteAvatar
		# keeps the real position on an inner _body node, so reading the outer
		# node reports (0,0) for everybody and looks like a replication failure
		# when nothing is wrong.
		parts.append(str(avatar.name))
		_trace_animation("remote", id, avatar)
		# The username label is a world-space node, so the camera magnifies it
		# along with everything else and it grows to three times its intended
		# size. Dividing it back out keeps it a constant size on screen. This is
		# done here rather than in RemoteAvatar because that compensation is
		# already correct for the default zoom, and the zoom is this scene's
		# choice, not the avatar's.
		var label := avatar.username_label()
		if label != null:
			label.scale = Vector2.ONE / CAMERA_ZOOM
			label.position = Vector2(-20, -140) / CAMERA_ZOOM
	_remotes.text = "remotes (%d): %s" % [ids.size(), " ".join(parts)]


func _on_roster(entries: Array) -> void:
	var names: Array = []
	for entry in entries:
		names.append(entry.get("username", "?"))
	_roster.text = "roster (%d): %s" % [entries.size(), " ".join(names)]
	if movement != null and movement.remote_ids() != _last_remote_ids:
		_last_remote_ids = movement.remote_ids()
		if _last_remote_ids.is_empty():
			_capture("roster-empty")
		else:
			_capture("roster-joined")


func _on_admitted(identity: Dictionary) -> void:
	_player_id = int(identity.get("player_id", 0))
	var character := OS.get_environment("TEST_CHARACTER")
	if character == "":
		character = "farmer_female"
	movement.start(_player_id, character)
	movement.remote_joined.connect(_on_remote_joined)
	movement.remote_left.connect(_on_remote_left)
	_phase = "admitted"
	_capture("admitted")
	print("RESULT admitted=%d username=%s" % [_player_id, username])
	_refresh_hud()


func _on_remote_joined(id: int) -> void:
	_capture("remote-joined-%d" % id)
	print("RESULT remote_joined=%d username=%s" % [id, username])


func _on_remote_left(id: int) -> void:
	_capture("remote-left-%d" % id)
	print("RESULT remote_left=%d username=%s" % [id, username])


func _on_rejected(reason: String) -> void:
	_phase = "rejected"
	_errors.append(reason)
	print("RESULT rejected=1 username=%s reason=%s" % [username, reason])


func _on_disconnected() -> void:
	_phase = "disconnected"
	print("RESULT disconnected=1 username=%s" % username)


func _capture(tag: String) -> void:
	if _screenshot_dir == "":
		return
	# Wait for the frame to actually land on the GPU before reading it back.
	#
	# RenderingServer.force_draw() only *submits* the frame; it does not wait for
	# it. Reading the viewport texture straight afterwards can therefore return a
	# null image, and saving that crashes the engine outright -- which is exactly
	# what happened, an access violation inside save_png while a client was being
	# admitted. frame_post_draw is the signal that says the frame is really there.
	await RenderingServer.frame_post_draw

	var image := get_viewport().get_texture().get_image()
	if image == null:
		_errors.append("no frame for %s" % tag)
		return

	_shot_index += 1
	var path := "%s/rendered-%s-%02d-%s.png" % [
		_screenshot_dir, _safe(username), _shot_index, _safe(tag),
	]
	var err := image.save_png(path)
	if err != OK:
		_errors.append("save_png %d" % err)
	else:
		print("RESULT screenshot=1 username=%s path=%s" % [username, path])


func _safe(value: String) -> String:
	return value.replace("/", "_").replace("\\", "_").replace(":", "_")


func _finish() -> void:
	var ids := movement.remote_ids()
	# Capture last, not first. Every earlier screenshot is taken the instant
	# something happens, which is exactly when the world is least populated: the
	# frame in which a remote joins is the frame before its avatar has been drawn.
	# A final shot shows the world as it actually stood.
	_refresh_hud()
	for fkey in _anim_max_frame.keys():
		print("RESULT animframe=1 scope_name=%s max_frame=%d" % [fkey, int(_anim_max_frame[fkey])])
	await _capture("final")
	print("RESULT summary=1 username=%s phase=%s player_id=%d position=%.1f,%.1f remotes=%d corrections=%d snapshots=%d errors=%s" % [
		username, _phase,
		_player_id,
		movement.local_position().x, movement.local_position().y,
		ids.size(), movement.correction_count(), movement.snapshot_count(),
		",".join(_errors),
	])
	get_tree().quit(0 if _errors.is_empty() else 1)
