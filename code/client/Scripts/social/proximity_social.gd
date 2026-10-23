extends CanvasLayer
## Drop into a world or the standalone social test scene.
var voice: Node
var community: Window
var _box: VBoxContainer
var _prompt: Label
var _status: Label
var _text: LineEdit
var _join: Button
var _talk: Button
var _nearby: OptionButton
var _peers: Array = []
var _bubbles: Dictionary = {}
var _players: Dictionary = {}
var _pending: Dictionary = {}
var _sending := false
var _connection_version := 0
var _manual_open := false
var _panel: PanelContainer
var _scroll: ScrollContainer
var _toggle: Button


func button(parent: Node, text: String, action: Callable) -> Button:
	var value := Button.new()
	value.text = text
	value.pressed.connect(action)
	parent.add_child(value)
	return value


func _ready() -> void:
	layer = 12
	voice = preload("res://Scripts/social/proximity_voice.gd").new()
	add_child(voice)
	community = preload("res://Scripts/social/community_window.gd").new()
	add_child(community)
	_panel = PanelContainer.new()
	_panel.position = Vector2(16, 90)
	_panel.theme = preload("res://Scripts/ui/lobby_theme.gd").theme()
	add_child(_panel)
	var outer := VBoxContainer.new()
	_panel.add_child(outer)
	_toggle = button(outer, "Nearby social / Gifts", func() -> void:
		_manual_open = not _manual_open
		_scroll.visible = _manual_open
		if not _manual_open:
			_text.release_focus()
			_text.hide()
		_fit_panel()
	)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.visible = false
	outer.add_child(_scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_box)
	_prompt = Label.new()
	_prompt.text = "Nearby social"
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_prompt)
	_nearby = OptionButton.new()
	_nearby.fit_to_longest_item = false
	_nearby.clip_text = true
	_box.add_child(_nearby)
	var row := GridContainer.new()
	row.columns = 2
	_box.add_child(row)
	button(row, "Write", func() -> void: _text.visible = true; _text.grab_focus())
	_join = button(row, "Join voice", func() -> void: voice.join_voice())
	button(row, "Gifts / Wishlist", func() -> void: community.open_for(_target()))
	button(row, "Dismiss", _dismiss)
	_text = LineEdit.new()
	_text.placeholder_text = "Nearby: visible to players in range (Enter)"
	_text.max_length = 500
	_text.visible = false
	_box.add_child(_text)
	_text.text_submitted.connect(_send)
	_text.focus_entered.connect(func() -> void: GameState.social_open = true)
	_text.focus_exited.connect(func() -> void: GameState.social_open = false)
	var controls := GridContainer.new()
	controls.columns = 2
	_box.add_child(controls)
	_talk = Button.new()
	_talk.text = "Hold Talk"
	controls.add_child(_talk)
	_talk.button_down.connect(func() -> void: voice.talk(true))
	_talk.button_up.connect(func() -> void: voice.talk(false))
	var deafen := CheckBox.new()
	deafen.text = "Deafen"
	controls.add_child(deafen)
	deafen.toggled.connect(func(value: bool) -> void: voice.set_deafened(value))
	button(controls, "Leave voice", func() -> void: voice.leave())
	button(controls, "Mute / unmute", func() -> void:
		if _target() > 0:
			voice.mute_player(_target(), not voice.muted_players.has(_target()))
	)
	var safety := GridContainer.new()
	safety.columns = 2
	_box.add_child(safety)
	button(safety, "Block player", _block)
	button(safety, "Report player", _report)
	button(safety, "Wishlist / Privacy", func() -> void: community.open_for())
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_status)
	voice.status_changed.connect(func(text: String) -> void: _status.text = text)
	voice.changed.connect(func() -> void:
		_join.disabled = not voice.session_id.is_empty()
		_talk.disabled = voice.session_id.is_empty()
		deafen.set_pressed_no_signal(voice.deafened)
	)
	_talk.disabled = true
	Global.session_changed.connect(func() -> void:
		_pending.clear()
		_text.clear()
		_clear()
	)
	APIClient.realtime.proximity_updated.connect(_proximity)
	APIClient.realtime.nearby_message_received.connect(_bubble)
	APIClient.realtime.snapshot_received.connect(_snapshot)
	APIClient.realtime.room_changed.connect(func(_room: String) -> void:
		_clear()
	)
	APIClient.realtime.connection_changed.connect(func(connected: bool) -> void:
		if not connected:
			_clear()
		_status.text = "Connected" if connected else "Reconnecting..."
	)
	get_viewport().size_changed.connect(_fit_panel)
	_fit_panel()


func _fit_panel() -> void:
	var viewport := get_viewport().get_visible_rect().size
	var width := minf(360, maxf(180, viewport.x - 32))
	_panel.custom_minimum_size.x = width
	_panel.size.x = width
	_scroll.custom_minimum_size = Vector2(0, minf(330, maxf(100, viewport.y - 170)))
	_panel.reset_size()


func _target() -> int:
	return _nearby.get_selected_id() if _nearby.item_count > 0 else 0


func _proximity(data: Dictionary) -> void:
	var selected := _target()
	_peers = data.get("nearby", [])
	_nearby.clear()
	var prompts := PackedStringArray()
	for peer in _peers:
		var id := int(peer["player_id"])
		_nearby.add_item(str(peer["username"]) + " · %d away" % int(peer["distance"]), id)
		if id == selected:
			_nearby.select(_nearby.item_count - 1)
		if peer.get("show_prompt", false):
			prompts.append(str(peer["username"]))
	_prompt.text = "Nearby: " + ", ".join(prompts) if not prompts.is_empty() else "Nearby social"
	_toggle.text = "Nearby social / Gifts (%d)" % _peers.size() if not _peers.is_empty() else "Nearby social / Gifts"
	# Presence updates must never expand a panel over gameplay.
	_scroll.visible = _manual_open
	# No focus is stolen when friends enter the perimeter.


func _dismiss() -> void:
	_manual_open = false
	_text.release_focus()
	_text.hide()
	_scroll.hide()
	_panel.reset_size()
	for peer in _peers:
		if peer.get("show_prompt", false):
			await APIClient.realtime.command("proximity.dismiss", {"target_id": int(peer["player_id"])})
	_text.release_focus()
	_text.hide()


func _send(body: String) -> void:
	body = body.strip_edges()
	if _sending or body.is_empty():
		return
	_sending = true
	var version := _connection_version
	if _pending.get("body") != body:
		_pending = {"body": body, "id": APIClient.realtime.new_request_id()}
	var response: Dictionary = await APIClient.realtime.command("chat", {"body": body}, str(_pending["id"]))
	_sending = false
	if version != _connection_version:
		return
	if response.get("ok", false):
		_pending.clear()
		if _text.text.strip_edges() == body:
			_text.clear()
		_text.release_focus()
		_status.text = "Sent"
	else:
		_status.text = str(response.get("message", "Could not send"))
		if not response.get("uncertain", false):
			_pending.clear()


func _snapshot(data: Dictionary) -> void:
	_players.clear()
	for player in data.get("players", []):
		_players[int(player["player_id"])] = player
	for id in _bubbles.keys():
		if not _players.has(id):
			_bubbles[id]["label"].queue_free()
			_bubbles.erase(id)


func _bubble(message: Dictionary) -> void:
	var id := int(message["sender_id"])
	var expiry := Time.get_unix_time_from_datetime_string(str(message.get("expires_at", "")).replace("+00:00", ""))
	var remaining := clampf(expiry - Time.get_unix_time_from_system(), 0, 10)
	if remaining <= 0:
		return
	if _bubbles.has(id):
		_bubbles[id]["label"].queue_free()
	var label := Label.new()
	label.text = str(message["body"]).left(180)
	label.tooltip_text = str(message["body"])
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 240
	label.size.x = 240
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	add_child(label)
	_bubbles[id] = {"label": label, "until": Time.get_ticks_msec() + int(remaining * 1000)}


func _process(_delta: float) -> void:
	for id in _bubbles.keys():
		var entry: Dictionary = _bubbles[id]
		if Time.get_ticks_msec() >= int(entry["until"]):
			entry["label"].queue_free()
			_bubbles.erase(id)
			continue
		var player: Dictionary = _players.get(id, {})
		if player.is_empty():
			continue
		var position := Vector2(float(player["x"]), float(player["y"]))
		var actor := get_tree().get_first_node_in_group("player") as Node2D
		if id == Global.player_id and actor != null:
			position = actor.global_position
		var screen: Vector2 = get_viewport().get_canvas_transform() * position
		entry["label"].position = screen + Vector2(-120, -85)


func _block() -> void:
	if _target() <= 0:
		return
	var response: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_POST, "/social/blocks", {"target_id": _target()})
	_status.text = "Player blocked." if response.get("ok", false) else APIClient.error_text(response)
	if response.get("ok", false):
		_clear()


func _report() -> void:
	if _target() <= 0:
		return
	var response: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_POST, "/social/reports", {"target_id": _target(), "reason": "harassment", "details": "Reported from proximity social controls"})
	_status.text = "Report submitted." if response.get("ok", false) else APIClient.error_text(response)


func _clear() -> void:
	_connection_version += 1
	_text.release_focus()
	_text.hide()
	_manual_open = false
	_scroll.hide()
	_panel.reset_size()
	for entry in _bubbles.values():
		entry["label"].queue_free()
	_bubbles.clear()
	_players.clear()
	_peers.clear()
	_nearby.clear()
	_prompt.text = "Nearby social"
