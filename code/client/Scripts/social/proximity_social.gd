extends CanvasLayer
## Drop into a world or the standalone social test scene.
var voice: Node
var _box: VBoxContainer
var _prompt: Label
var _status: Label
var _text: LineEdit
var _join: Button
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
var _voice_panel: PanelContainer
var _peer_cards: VBoxContainer
var _context_busy := false
var _context_actions: GridContainer


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
	_panel = PanelContainer.new()
	_panel.theme = preload("res://Scripts/ui/lobby_theme.gd").theme()
	add_child(_panel)
	_panel.resized.connect(_place_panel)
	var outer := VBoxContainer.new(); _panel.add_child(outer)
	_toggle = button(outer, "Nearby · 0", func():
		if _voice_panel.visible and _manual_open: _show_nearby(); _fit_panel.call_deferred(); return
		_manual_open = not _manual_open
		_scroll.visible = _manual_open
		if _manual_open: _show_nearby()
		if not _manual_open: _text.release_focus(); _text.hide()
		_fit_panel.call_deferred()
	)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.visible = false; outer.add_child(_scroll)
	_box = VBoxContainer.new(); _box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _box.add_theme_constant_override("separation", 8); _scroll.add_child(_box)
	_box.minimum_size_changed.connect(_fit_panel.call_deferred)
	_prompt = Label.new(); _prompt.text = "No players nearby. Explore the world to meet someone."
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; _box.add_child(_prompt)
	_nearby = OptionButton.new(); _nearby.fit_to_longest_item = false; _nearby.clip_text = true; _box.add_child(_nearby); _nearby.hide()
	_peer_cards = VBoxContainer.new(); _box.add_child(_peer_cards)
	var row := HBoxContainer.new(); _box.add_child(row)
	button(row, "Nearby Chat", func(): _text.show(); _text.grab_focus(); _fit_panel.call_deferred())
	_join = button(row, "Join Voice", func(): open_voice(); voice.join_voice())
	_text = LineEdit.new(); _text.placeholder_text = "Nearby message · Enter to send"; _text.max_length = 500; _text.hide(); _box.add_child(_text)
	_text.text_submitted.connect(_send)
	_text.focus_entered.connect(func(): GameState.social_open = true)
	_text.focus_exited.connect(func(): GameState.social_open = false)
	var actions := GridContainer.new(); _context_actions = actions; actions.columns = 2; _box.add_child(actions); actions.hide()
	button(actions, "View profile", _profile)
	button(actions, "Add Friend", _add_friend)
	button(actions, "Mute player", func():
		if _target() > 0: voice.mute_player(_target(), not voice.muted_players.has(_target())); _render_peers()
	)
	button(actions, "Block", _block)
	button(actions, "Report", _report)
	button(actions, "Close", _dismiss)
	_status = Label.new(); _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; _box.add_child(_status)
	_voice_panel = preload("res://Scripts/social/voice_panel.gd").new(); _voice_panel.voice = voice; _box.add_child(_voice_panel); _voice_panel.hide()
	_voice_panel.visibility_changed.connect(func(): _fit_panel.call_deferred())
	Global.session_changed.connect(func(): _pending.clear(); _text.clear(); _clear())
	APIClient.realtime.proximity_updated.connect(_proximity)
	APIClient.realtime.nearby_message_received.connect(_bubble)
	APIClient.realtime.snapshot_received.connect(_snapshot)
	APIClient.realtime.room_changed.connect(func(_room: String): _clear())
	APIClient.realtime.connection_changed.connect(func(connected: bool):
		if not connected: _clear()
		_prompt.text = "Choose a nearby player." if connected and not _peers.is_empty() else "No players nearby."
	)
	get_viewport().size_changed.connect(_fit_panel)
	_fit_panel()

func _fit_panel() -> void:
	if not is_inside_tree(): return
	var viewport := get_viewport().get_visible_rect().size
	var width := minf(390 if _manual_open else 190, maxf(180, viewport.x - 48))
	_panel.custom_minimum_size.x = width
	_panel.size.x = width
	var limit := minf(540 if _voice_panel.visible else 430, maxf(160, viewport.y - 220))
	_scroll.custom_minimum_size = Vector2(0, minf(limit, maxf(100, _box.get_combined_minimum_size().y)))
	_panel.reset_size()
	_place_panel()

func _place_panel() -> void:
	if not is_inside_tree(): return
	var viewport := get_viewport().get_visible_rect().size
	_panel.position = Vector2(24, maxf(20, viewport.y - _panel.size.y - 24))

func open_voice() -> void:
	_manual_open = true; _scroll.show()
	for child in _box.get_children(): child.hide()
	_voice_panel.show()
	_toggle.text = "Back to Nearby"
	_fit_panel.call_deferred()

func _show_nearby() -> void:
	for child in _box.get_children(): child.show()
	_voice_panel.hide(); _nearby.hide(); _text.hide(); _context_actions.hide()
	_toggle.text = "Nearby · %d" % _peers.size()

func _render_peers() -> void:
	for child in _peer_cards.get_children(): _peer_cards.remove_child(child); child.queue_free()
	for peer in _peers:
		var caption := str(peer.get("username", "Player")) + " · %d away" % int(peer.get("distance", 0))
		var state := "Voice available" if peer.get("can_voice", false) else "Voice unavailable"
		if voice.muted_players.has(int(peer.get("player_id", 0))): state = "Muted by you"
		var card := button(_peer_cards, caption + "\n" + state, func():
			for index in _nearby.item_count:
				if _nearby.get_item_id(index) == int(peer["player_id"]): _nearby.select(index)
			_context_actions.show(); _fit_panel.call_deferred()
		)
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.add_theme_font_size_override("font_size", 17)
		card.clip_text = true

func _profile() -> void:
	for peer in _peers:
		if int(peer["player_id"]) == _target():
			_status.text = str(peer["username"]) + (" · Friend" if peer.get("friend", false) else " · Nearby player") + "\nDistance: %d · %s" % [int(peer.get("distance", 0)), "Voice available" if peer.get("can_voice", false) else "Voice unavailable"]

func _add_friend() -> void:
	if _target() <= 0 or _context_busy: return
	_context_busy = true; _status.text = "Sending request…"
	var version := _connection_version
	var response: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_POST, "/social/requests", {"target_id": _target()})
	_context_busy = false
	if version == _connection_version and not response.get("stale", false):
		_status.text = "Friend request sent." if response.get("ok", false) else APIClient.error_text(response)


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
	_prompt.text = "Choose a nearby player." if not _peers.is_empty() else "No players nearby. Explore the world to meet someone."
	_toggle.text = "Back to Nearby" if _voice_panel.visible else "Nearby · %d" % _peers.size()
	_render_peers()
	_fit_panel.call_deferred()
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
	_join.text = "Voice controls" if not voice.session_id.is_empty() else "Join Voice"
	for control in _context_actions.get_children():
		control.disabled = _context_busy and control.text != "Close"
		if control.text == "Add Friend":
			for peer in _peers:
				if int(peer["player_id"]) == _target() and peer.get("friend", false): control.disabled = true
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
	if _target() <= 0 or _context_busy:
		return
	_context_busy = true
	var version := _connection_version
	_status.text = "Blocking player…"
	var response: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_POST, "/social/blocks", {"target_id": _target()})
	_context_busy = false
	if version != _connection_version or response.get("stale", false): return
	_status.text = "Player blocked." if response.get("ok", false) else APIClient.error_text(response)
	if response.get("ok", false):
		_clear()


func _report() -> void:
	if _target() <= 0 or _context_busy:
		return
	_context_busy = true
	var version := _connection_version
	_status.text = "Submitting report…"
	var response: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_POST, "/social/reports", {"target_id": _target(), "reason": "harassment", "details": "Reported from proximity social controls"})
	_context_busy = false
	if version != _connection_version or response.get("stale", false): return
	_status.text = "Report submitted." if response.get("ok", false) else APIClient.error_text(response)


func _clear() -> void:
	if not is_inside_tree(): return
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
	_prompt.text = "No players nearby."
	_toggle.text = "Nearby · 0"
	_render_peers()
	_fit_panel.call_deferred()
