extends Node2D
## A real, rendered Godot window used to verify the multiplayer stack outside the
## headless harness.
##
## It performs the real path only: request a ticket from FastAPI, open a real UDP
## connection, present the ticket, and display whatever the backend decided. It
## loads no production gameplay scene, so it cannot disturb the normal game, and
## it never touches ``RealtimeClient`` -- there is only ever one movement
## authority.
##
## Environment:
##   TEST_API_URL     backend base url        (default http://127.0.0.1:8000)
##   TEST_TOKEN       the player's access token
##   TEST_USERNAME    label shown in the window
##   TEST_HOST        multiplayer host         (default 127.0.0.1)
##   TEST_PORT        multiplayer udp port     (default 24567)
##   TEST_SCREENSHOT_DIR  write a PNG per milestone into this directory
##   TEST_SCENARIO    "presence" runs the scripted disconnect/reconnect check;
##                     unset leaves the window open for manual use
##   TEST_EXPECT_ROSTER  roster size that counts as "both connected"
##   TEST_AUTO_START  0 to open the window without connecting
##
## Prints RESULT lines so a supervising process can assert on them, and also
## shows the same information on screen for a human.

const SCENARIO_PRESENCE := "presence"

var client: MultiplayerClient
var link: NetworkLink
var username := ""
var host := NetworkConfig.DEFAULT_HOST
var port := NetworkConfig.DEFAULT_PORT
var api_url := "http://127.0.0.1:8000"
var token := ""

var _status_label: Label
var _roster_label: Label
var _hint_label: Label
var _roster: Array = []
var _screenshot_dir := ""
var _shot_index := 0
var _phase := "starting"
var _phase_elapsed := 0.0
var _errors: Array = []
var _shots := 0


func _ready() -> void:
	api_url = OS.get_environment("TEST_API_URL")
	token = OS.get_environment("TEST_TOKEN")
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

	# Direct child of the scene root: NetworkLink's relative RPC path depends on it.
	link = NetworkLink.new()
	link.name = "NetworkLink"
	add_child(link)
	link.roster_received.connect(_on_roster)

	_build_ui()
	_apply_window_title()

	client = MultiplayerClient.new()
	add_child(client)
	client.configure(api_url, token)
	client.admitted.connect(_on_admitted)
	client.rejected.connect(_on_rejected)
	client.disconnected.connect(_on_disconnected)

	print("[RenderedClient] display=%s starting host=%s port=%d" % [DisplayServer.get_name(), host, port])

	if OS.get_environment("TEST_AUTO_START") == "0":
		_phase = "idle"
		return
	_phase = "await_admitted"
	client.connect_to_server(host, port)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(560, 0)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Wanderville multiplayer — %s" % username
	title.add_theme_font_override("font", WoodPanel.PIXEL_FONT)
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)

	_status_label = _new_label(box)
	_roster_label = _new_label(box)
	_hint_label = _new_label(box)
	_hint_label.text = "F1 disconnect    F2 reconnect"
	_hint_label.modulate = Color(1, 1, 1, 0.7)


func _new_label(parent: Node) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", WoodPanel.PIXEL_FONT)
	label.add_theme_font_size_override("font_size", 22)
	parent.add_child(label)
	return label


func _apply_window_title() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_title("Wanderville MP — %s" % username)


# ── admission callbacks ────────────────────────────────────────────────────


func _on_admitted(identity: Dictionary) -> void:
	_result({
		"ok": true,
		"event": "admitted",
		"username": username,
		"player_id": int(identity.get("player_id", 0)),
		"server_username": str(identity.get("username", "")),
		"room": str(identity.get("room", "")),
		"server_id": str(identity.get("server_id", "")),
	})
	_screenshot("admitted")


func _on_rejected(reason: String) -> void:
	_errors.append("rejected: " + reason)
	_result({"ok": false, "event": "rejected", "username": username, "reason": reason})
	_screenshot("rejected")
	get_tree().quit(1)


func _on_disconnected() -> void:
	_roster = []


# ── roster ─────────────────────────────────────────────────────────────────


func _on_roster(entries: Array) -> void:
	_roster = entries
	print("[RenderedClient] roster of %d received" % entries.size())


func _others() -> Array:
	var mine := 0
	if client != null:
		mine = int(client.identity.get("player_id", 0))
	var found: Array = []
	for entry in _roster:
		if int(entry.get("player_id", 0)) != mine:
			found.append(entry)
	return found


# ── scripted scenario ──────────────────────────────────────────────────────


func _process(delta: float) -> void:
	_update_labels()
	if OS.get_environment("TEST_SCENARIO") != SCENARIO_PRESENCE:
		_manual_keys()
		return
	_phase_elapsed += delta
	match _phase:
		"await_admitted":
			if client != null and client.is_admitted():
				_enter("await_roster")
		"await_roster":
			var wanted := int(OS.get_environment("TEST_EXPECT_ROSTER"))
			if wanted <= 0:
				wanted = 2
			if _roster.size() >= wanted:
				_roster_reached(wanted)
		"hold_before_disconnect":
			if _phase_elapsed >= 2.0:
				_do_disconnect("disconnect")
		"await_dropped":
			if _roster.size() <= 1 or _phase_elapsed > 10.0:
				_enter("hold_before_reconnect")
		"hold_before_reconnect":
			if _phase_elapsed >= 1.5:
				# A reconnect must fetch a *new* ticket; the token is reused, so
				# the backend mints a fresh one for the new attempt.
				client.connect_to_server(host, port)
				_enter("await_readmitted")
		"await_readmitted":
			if client != null and client.is_admitted():
				_screenshot("readmitted")
				_enter("hold_after_reconnect")
		"hold_after_reconnect":
			var wanted := maxi(2, int(OS.get_environment("TEST_EXPECT_ROSTER")))
			if _phase_elapsed >= 2.5 and _roster.size() >= wanted:
				_finish_scenario()
		"await_peer_completion":
			var directory := OS.get_environment("TEST_SCENARIO_SYNC_DIR")
			var completed := 0
			for file in DirAccess.get_files_at(directory):
				if file.ends_with(".complete"):
					completed += 1
			if completed >= 2:
				client.disconnect_from_server()
				get_tree().quit(0 if _errors.is_empty() else 1)


func _roster_reached(wanted: int) -> void:
	_result({
		"ok": true,
		"event": "roster_full",
		"username": username,
		"roster_size": _roster.size(),
		"expected": wanted,
		"others": _others().map(func(e): return int(e.get("player_id", 0))),
	})
	_screenshot("both-connected")
	_enter("hold_before_disconnect")


func _do_disconnect(tag: String) -> void:
	client.disconnect_from_server()
	_roster = []
	_result({"ok": true, "event": "disconnected", "username": username, "phase": tag})
	_screenshot(tag)
	_enter("await_dropped")


func _enter(phase: String) -> void:
	_phase = phase
	_phase_elapsed = 0.0


func _finish_scenario() -> void:
	var others := _others()
	_result({
		"ok": _errors.is_empty(),
		"event": "scenario_complete",
		"username": username,
		"player_id": int(client.identity.get("player_id", 0)),
		"roster_size": _roster.size(),
		"others": others.map(func(e): return int(e.get("player_id", 0))),
		"errors": _errors,
		"screenshots": _shots,
	})
	_screenshot("complete")
	var directory := OS.get_environment("TEST_SCENARIO_SYNC_DIR")
	if not directory.is_empty():
		var marker := FileAccess.open(directory.path_join(username + ".complete"), FileAccess.WRITE)
		marker.store_string("complete")
		marker.close()
		_enter("await_peer_completion")
		return
	client.disconnect_from_server()
	get_tree().quit(0 if _errors.is_empty() else 1)


func _manual_keys() -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		client.disconnect_from_server()
	if Input.is_action_just_pressed("ui_accept"):
		client.connect_to_server(host, port)


# ── display ────────────────────────────────────────────────────────────────


func _update_labels() -> void:
	var state_name := "IDLE"
	if client != null:
		state_name = MultiplayerClient.State.keys()[client.state]
	var identity := client.identity if client != null else {}
	var lines := [
		"state: %s" % state_name,
		"player_id: %s" % str(identity.get("player_id", "-")),
		"backend identity: %s" % str(identity.get("username", "-")),
		"room: %s" % str(identity.get("room", "-")),
		"server: %s" % str(identity.get("server_id", "-")),
		"phase: %s" % _phase,
	]
	if _status_label != null:
		_status_label.text = "\n".join(lines)
	if _roster_label != null:
		var others := _others()
		var names: Array = []
		for entry in others:
			names.append("%s (id %s)" % [str(entry.get("username", "?")), str(entry.get("player_id", "?"))])
		_roster_label.text = "roster: %d total, %d other(s)%s" % [
			_roster.size(), others.size(),
			("\n  - " + "\n  - ".join(names)) if not names.is_empty() else "",
		]


# ── evidence ───────────────────────────────────────────────────────────────


func _result(payload: Dictionary) -> void:
	print("RESULT " + JSON.stringify(payload))


func _screenshot(tag: String) -> void:
	if _screenshot_dir == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_shot_index += 1
	var path := "%s/%02d-%s-%s.png" % [_screenshot_dir, _shot_index, username, tag]
	var err := image.save_png(path)
	if err == OK:
		_shots += 1
		print("[RenderedClient] screenshot %s" % path)
	else:
		print("[RenderedClient] screenshot failed %s err=%d" % [path, err])