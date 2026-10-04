extends VBoxContainer

signal attention_changed(count: int)

@onready var panel: PanelContainer = %Panel
@onready var chat: VBoxContainer = %Chat
@onready var friends: VBoxContainer = %Friends
@onready var mode: OptionButton = %Mode
@onready var history: RichTextLabel = %History
@onready var message: LineEdit = %Message
@onready var view: OptionButton = %View
@onready var people: ItemList = %Players
@onready var status: Label = %Status
var _nearby: Array = []
var _private: Dictionary = {}
var _names: Dictionary = {}
var _target := 0
var _rows: Array = []
var _loading := false
var _acting := false
var _sending := false
var _elapsed := 0.0
var _revision := 0
var _drafts: Dictionary = {}
var _draft_key := "nearby"
var _unread := 0
var _unread_channels: Dictionary = {}
var _session := -1


func _ready() -> void:
	_session = Global.session_version
	mode.select(0)
	view.select(0)
	WoodPanel.apply_field_style(message)
	WoodPanel.apply_field_style(%Search)
	WoodPanel.apply_status_label(status)
	%ChatButton.pressed.connect(func() -> void: _toggle(true))
	%FriendsButton.pressed.connect(func() -> void: _toggle(false))
	%Send.pressed.connect(_send)
	message.text_submitted.connect(func(_text: String) -> void: _send())
	%Find.pressed.connect(_load_people)
	%Search.text_submitted.connect(func(_text: String) -> void: _load_people())
	view.item_selected.connect(_view_changed)
	mode.item_selected.connect(_mode_changed)
	people.item_selected.connect(func(_index: int) -> void: _actions())
	%Primary.pressed.connect(_primary)
	%Decline.pressed.connect(func() -> void: _act("decline"))
	%More.get_popup().id_pressed.connect(func(id: int) -> void: _act("remove" if id == 0 else "block"))
	APIClient.realtime.nearby_message_received.connect(_nearby_message)
	APIClient.realtime.direct_message_received.connect(_direct_message)
	APIClient.realtime.conversation_polled.connect(func(target: int) -> void:
		if target == _target and mode.selected == 1:
			status.text = "No messages yet." if _private.get(target, []).is_empty() else "Private conversation."
	)
	APIClient.realtime.request_failed.connect(_failure)
	APIClient.realtime.connection_changed.connect(_connection)
	APIClient.realtime.snapshot_received.connect(_snapshot)
	GameState.backend_error.connect(_failure)
	APIClient.session_expired.connect(_expired)
	_actions()
	_render_history()


func _toggle(show_chat: bool) -> void:
	_drafts[_draft_key] = message.text
	set_open(true)
	chat.visible = show_chat
	friends.visible = not show_chat
	_revision += 1
	_loading = false
	_stop_watch()
	if panel.visible:
		if show_chat:
			_mode_changed(mode.selected)
			message.grab_focus()
		else:
			_load_people()


func set_open(value: bool) -> void:
	_drafts[_draft_key] = message.text
	visible = value
	panel.visible = value
	GameState.social_open = value
	if value:
		if chat.visible:
			_mode_changed(mode.selected)
		else:
			_load_people()
	else:
		_stop_watch()
		message.release_focus()
		%Search.release_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if panel.visible and event.is_action_pressed("ui_cancel"):
		set_open(false)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _session != Global.session_version:
		_session = Global.session_version
		_stop_watch()
		_nearby.clear()
		_private.clear()
		_names.clear()
		_drafts.clear()
		_rows.clear()
		_target = 0
		_unread = 0
		_unread_channels.clear()
		message.clear()
		people.clear()
		%Search.clear()
		_render_history()
		set_open(false)
		attention_changed.emit(0)
	if not panel.visible or not friends.visible or view.selected == 2:
		return
	_elapsed += delta
	if _elapsed >= 5.0 and not _loading and not _acting:
		_elapsed = 0.0
		_load_people()


func _view_changed(_index: int) -> void:
	_revision += 1
	_loading = false
	%SearchRow.visible = view.selected == 2
	_rows.clear()
	people.clear()
	_actions()
	_load_people()


func _load_people() -> void:
	if _loading or not panel.visible or not friends.visible:
		return
	var paths := ["/social/friends", "/social/requests", "/social/search?q=" + str(%Search.text).strip_edges().uri_encode(), "/social/blocks"]
	if view.selected == 2 and str(%Search.text).strip_edges().length() < 2:
		status.text = "Enter at least two username characters."
		return
	_loading = true
	var revision := _revision
	var selected_id := int(_selected().get("id", 0))
	status.text = "Loading..."
	var response: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_GET, paths[view.selected])
	if revision != _revision or response.get("stale", false):
		return
	_loading = false
	if not response.get("ok", false):
		status.text = APIClient.error_text(response)
		return
	_rows = APIClient.data_of(response)
	people.clear()
	for row in _rows:
		var id := int(row.get("id", row.get("blocked_id", 0)))
		row["id"] = id
		var username := str(row.get("username", _names.get(id, "Player %d" % id)))
		_names[id] = username
		var suffix := "online" if row.get("online", false) else "offline"
		if view.selected == 1:
			suffix = "sent" if int(row.get("requested_by", 0)) == Global.player_id else "incoming"
		people.add_item(username + ("" if view.selected == 3 else "  ·  " + suffix))
		if id == selected_id:
			people.select(people.item_count - 1)
	status.text = "No players here yet." if _rows.is_empty() else "Select a player."
	_actions()


func _selected() -> Dictionary:
	var selected := people.get_selected_items()
	return _rows[selected[0]] if not selected.is_empty() and selected[0] < _rows.size() else {}


func _actions() -> void:
	var row := _selected()
	var incoming := view.selected == 1 and int(row.get("requested_by", 0)) != Global.player_id
	%Primary.text = ["Message", "Accept" if incoming else "Cancel", "Add friend", "Unblock"][view.selected]
	%Primary.disabled = row.is_empty() or _acting
	%Decline.visible = incoming and not row.is_empty()
	%Decline.disabled = _acting
	%More.disabled = row.is_empty() or view.selected == 3 or _acting
	var popup: PopupMenu = %More.get_popup()
	popup.clear()
	if view.selected == 0:
		popup.add_item("Remove friend", 0)
	popup.add_item("Block player", 1)


func _primary() -> void:
	var row := _selected()
	if row.is_empty() or _acting:
		return
	if view.selected == 0:
		_stop_watch()
		_target = int(row["id"])
		mode.set_item_text(1, "Private · " + str(_names[_target]))
		mode.select(1)
		_toggle(true)
	else:
		var action := "accept" if int(row.get("requested_by", 0)) != Global.player_id else "remove"
		_act(action if view.selected == 1 else ("request" if view.selected == 2 else "unblock"))


func _act(action: String) -> void:
	var row := _selected()
	if row.is_empty() or _acting:
		return
	_acting = true
	_actions()
	var target := int(row["id"])
	var path := "/social/friends/%d" % target
	var body := {"action": action}
	match action:
		"request":
			path = "/social/requests"
			body = {"target_id": target}
		"block":
			path = "/social/blocks"
			body = {"target_id": target}
		"unblock":
			path = "/social/blocks/%d/remove" % target
			body = {}
	var response: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_POST, path, body)
	_acting = false
	if response.get("stale", false):
		return
	if action in ["block", "remove"] and target == _target:
		_stop_watch()
		_target = 0
		mode.select(0)
	if action == "block" and response.get("ok", false):
		_private.erase(target)
		_nearby = _nearby.filter(func(item: Dictionary) -> bool: return int(item.get("sender_id", 0)) != target)
	await _load_people()
	status.text = "Updated." if response.get("ok", false) else APIClient.error_text(response)
	_actions()


func _mode_changed(_index: int) -> void:
	_drafts[_draft_key] = message.text
	_draft_key = "nearby" if mode.selected == 0 else str(_target)
	message.text = str(_drafts.get(_draft_key, ""))
	if visible and chat.visible:
		_unread_channels.erase(_draft_key)
		_update_unread()
	_stop_watch()
	if mode.selected == 1 and _target > 0 and panel.visible and chat.visible:
		var records: Array = _private.get(_target, [])
		var after := int(records[-1]["id"]) if not records.is_empty() else 0
		APIClient.realtime.watch_conversation(_target, after)
		status.text = "Loading private conversation..."
	else:
		status.text = "Choose Message from Friends to open a private conversation." if mode.selected == 1 else "Nearby players within chat range."
	_render_history()


func _stop_watch() -> void:
	if _target > 0:
		APIClient.realtime.unwatch_conversation(_target)


func _send() -> void:
	var body := message.text.strip_edges()
	var sent_key := _draft_key
	if _sending or body == "":
		return
	if mode.selected == 1 and _target == 0:
		status.text = "Choose a friend first."
		return
	_sending = true
	%Send.disabled = true
	status.text = "Sending..."
	var response: Dictionary
	if mode.selected == 0:
		response = await APIClient.authenticated(HTTPClient.METHOD_POST, "/realtime/chat", {"body": body})
	else:
		response = await APIClient.send_direct_message(_target, body)
	_sending = false
	%Send.disabled = false
	if response.get("stale", false):
		return
	if response.get("ok", false):
		if _draft_key == sent_key and message.text.strip_edges() == body:
			message.clear()
		if str(_drafts.get(sent_key, "")).strip_edges() == body:
			_drafts.erase(sent_key)
		var data: Variant = APIClient.data_of(response)
		if data is Dictionary and data.has("receiver_id"):
			_direct_message(data)
		status.text = "Sent."
	else:
		status.text = "Delivery unconfirmed. Check history before resending." if int(response.get("status_code", 0)) == 0 else APIClient.error_text(response)


func _snapshot(snapshot: Dictionary) -> void:
	for player in snapshot.get("players", []):
		_names[int(player["player_id"])] = str(player.get("username", "Player"))


func _nearby_message(record: Dictionary) -> void:
	_nearby.append(record)
	if not visible or not chat.visible or mode.selected != 0:
		_unread_channels["nearby"] = int(_unread_channels.get("nearby", 0)) + 1
		_update_unread()
	if _nearby.size() > 200:
		_nearby.pop_front()
	_render_history()


func _direct_message(record: Dictionary) -> void:
	var other := int(record["sender_id"]) if int(record["sender_id"]) != Global.player_id else int(record["receiver_id"])
	var records: Array = _private.get(other, [])
	for old in records:
		if int(old["id"]) == int(record["id"]):
			return
	records.append(record)
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	if records.size() > 200:
		records.pop_front()
	_private[other] = records
	if int(record["sender_id"]) != Global.player_id and (not visible or not chat.visible or mode.selected != 1 or _target != other):
		_unread_channels[str(other)] = int(_unread_channels.get(str(other), 0)) + 1
		_update_unread()
	status.text = "Private conversation."
	_render_history()


func _update_unread() -> void:
	_unread = 0
	for count in _unread_channels.values():
		_unread += int(count)
	attention_changed.emit(_unread)


func _render_history() -> void:
	var bar := history.get_v_scroll_bar()
	var at_bottom := bar.value >= bar.max_value - bar.page - 3.0
	var previous := bar.value
	var records: Array = _nearby if mode.selected == 0 else _private.get(_target, [])
	var lines: PackedStringArray = []
	for record in records:
		var sender := int(record["sender_id"])
		var sender_name := Global.username if sender == Global.player_id else str(_names.get(sender, "Player %d" % sender))
		lines.append(sender_name + ": " + str(record["body"]))
	history.text = "No messages yet." if lines.is_empty() else "\n".join(lines)
	if at_bottom:
		history.call_deferred("scroll_to_line", maxi(0, history.get_line_count() - 1))
	else:
		bar.set_deferred("value", previous)


func _failure(text: String) -> void:
	status.text = text
	if not panel.visible:
		%ChatButton.tooltip_text = text


func _connection(connected: bool) -> void:
	status.text = "Connected." if connected else "Reconnecting..."


func _expired() -> void:
	Global.clear_session()
	SceneManager.goto_login()


func _exit_tree() -> void:
	_stop_watch()
	GameState.social_open = false
