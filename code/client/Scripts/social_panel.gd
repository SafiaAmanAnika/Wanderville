extends VBoxContainer

signal attention_changed(count: int)

const MENU_REMOVE := 0
const MENU_INVITE := 1
const MENU_BLOCK := 2
const MENU_VISITORS := 3
const MENU_DECLINE := 4
const MENU_BACK := 5
const VIEW_INVITATIONS := 4

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
# "people" is the view's own list; "visitor" is the temporary occupancy list a
# host opens to eject somebody. The label and the primary action follow it.
var _people_kind := "people"


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
	%Decline.pressed.connect(_decline)
	%More.get_popup().id_pressed.connect(_menu_action)
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
	_people_kind = "people"
	%SearchRow.visible = view.selected == 2
	_rows.clear()
	people.clear()
	_actions()
	_load_people()


func _load_people() -> void:
	if _loading or not panel.visible or not friends.visible:
		return
	_people_kind = "people"
	var paths := [
		"/social/friends",
		"/social/requests",
		"/social/search?q=" + str(%Search.text).strip_edges().uri_encode(),
		"/social/blocks",
		"/farm/visiting/invitations",
	]
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
		if view.selected == 4:
			# An invitation is identified by its own id, not the host's, and the
			# host is named explicitly by the server so the guest knows who is
			# asking them into their farm.
			people.add_item(
				str(row.get("host_username", "Player"))
				+ "  ·  "
				+ str(row.get("world_name", ""))
			)
			if id == selected_id:
				people.select(people.item_count - 1)
			continue
		var username := str(row.get("username", _names.get(id, "Player %d" % id)))
		_names[id] = username
		var suffix := "online" if row.get("online", false) else "offline"
		if view.selected == 1:
			suffix = "sent" if int(row.get("requested_by", 0)) == Global.player_id else "incoming"
		people.add_item(username + ("" if view.selected == 3 else "  ·  " + suffix))
		if id == selected_id:
			people.select(people.item_count - 1)
	status.text = "No players here yet." if _rows.is_empty() else "Select a player."
	if view.selected == 4 and not _rows.is_empty():
		status.text = "Select an invitation."
	_actions()


func _selected() -> Dictionary:
	var selected := people.get_selected_items()
	return _rows[selected[0]] if not selected.is_empty() and selected[0] < _rows.size() else {}


func _actions() -> void:
	var row := _selected()
	var visitors := _people_kind == "visitor"
	var invitations := view.selected == VIEW_INVITATIONS
	var incoming := view.selected == 1 and int(row.get("requested_by", 0)) != Global.player_id
	if visitors:
		%Primary.text = "Remove visitor"
	elif invitations:
		%Primary.text = "Visit farm"
	elif view.selected == 3:
		%Primary.text = "Unblock"
	else:
		%Primary.text = ["Message", "Accept" if incoming else "Cancel", "Add friend", "Unblock"][view.selected]
	%Primary.disabled = row.is_empty() or _acting
	%Decline.visible = (incoming or invitations) and not visitors and not row.is_empty()
	%Decline.disabled = _acting
	%More.disabled = row.is_empty() or ((view.selected == 3 or visitors) and not invitations) or _acting
	var popup: PopupMenu = %More.get_popup()
	popup.clear()
	if visitors:
		popup.add_item("Back to friends", MENU_BACK)
	elif invitations:
		popup.add_item("Decline invitation", MENU_DECLINE)
	elif view.selected == 0:
		popup.add_item("Remove friend", MENU_REMOVE)
		# Only friends can be invited; being merely searchable is not enough.
		popup.add_item("Invite to my farm", MENU_INVITE)
	if not visitors and not invitations and view.selected != 3:
		popup.add_item("Block player", MENU_BLOCK)
	# A visitor always gets an explicit way out; a host can open the occupancy
	# list to eject whoever is standing in their farm.
	popup.add_item("Leave this farm" if GameState.read_only else "Visitors in my farm", MENU_VISITORS)


func _menu_action(id: int) -> void:
	match id:
		MENU_REMOVE:
			_act("remove")
		MENU_BLOCK:
			_act("block")
		MENU_INVITE:
			_act("invite_farm")
		MENU_VISITORS:
			_farm_visitors()
		MENU_DECLINE:
			_invitation_action("decline")
		MENU_BACK:
			_back_to_people()


func _back_to_people() -> void:
	_people_kind = "people"
	people.clear()
	_rows.clear()
	_actions()
	await _load_people()


func _primary() -> void:
	var row := _selected()
	if row.is_empty() or _acting:
		return
	if _people_kind == "visitor":
		_remove_visitor()
		return
	if view.selected == VIEW_INVITATIONS:
		_invitation_action("accept")
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


func _decline() -> void:
	# The same button declines a friend request and an unanswered farm
	# invitation, depending on which list is open.
	if view.selected == VIEW_INVITATIONS:
		_invitation_action("decline")
	else:
		_act("decline")


func _invitation_action(action: String) -> void:
	var row := _selected()
	if row.is_empty() or _acting:
		return
	var invitation_id := int(row["id"])
	_acting = true
	_actions()
	var response: Dictionary
	match action:
		"accept":
			response = await APIClient.accept_farm_invitation(invitation_id)
		_:
			response = await APIClient.decline_farm_invitation(invitation_id)
	_acting = false
	if response.get("stale", false):
		return
	if not bool(response.get("ok", false)):
		status.text = APIClient.error_text(response)
		_actions()
		return
	var data: Variant = APIClient.data_of(response)
	if action == "accept" and data is Dictionary:
		# The accept payload describes the new visit, but only /farm/visiting/
		# session is the authoritative owned/current pair, so the session is
		# re-read rather than guessed from the accept response.
		GameState.apply_session(await _visit_session())
		# Move the socket to the host's world before reloading, so the first
		# snapshot rendered is the farm the player was just admitted to.
		APIClient.realtime.enter_world(GameState.current_world_id())
		await GameState.refresh_gameplay()
		status.text = "You are visiting this farm. Everything here is read-only until you leave."
	else:
		status.text = "Invitation declined."
	await _load_people()
	_actions()


func _visit_session() -> Dictionary:
	var response: Dictionary = await APIClient.visit_session()
	var data: Variant = APIClient.data_of(response)
	return data if bool(response.get("ok", false)) and data is Dictionary else {}


func _act(action: String) -> void:
	var row := _selected()
	if row.is_empty() or _acting:
		return
	if action == "invite_farm":
		# Awaited so a caller that inspects the status line afterwards sees the
		# answer to the request it just made instead of the one from before it.
		await _invite_to_farm(int(row["id"]))
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


func _invite_to_farm(target: int) -> void:
	if _acting:
		return
	_acting = true
	_actions()
	var response: Dictionary = await APIClient.invite_to_farm(target)
	_acting = false
	if response.get("stale", false):
		return
	status.text = (
		"Invitation sent. It lapses if they ignore it."
		if bool(response.get("ok", false))
		else APIClient.error_text(response)
	)
	_actions()


func _farm_visitors() -> void:
	if GameState.read_only:
		_leave_farm()
		return
	if _acting:
		return
	_acting = true
	_actions()
	var response: Dictionary = await APIClient.farm_visitors()
	_acting = false
	if response.get("stale", false):
		return
	var data: Variant = APIClient.data_of(response)
	if not bool(response.get("ok", false)) or not data is Dictionary:
		status.text = APIClient.error_text(response)
		_actions()
		return
	var visitors: Variant = data.get("visitors", [])
	var count := int(data.get("visitor_count", 0))
	var limit := int(data.get("visitor_limit", 0))
	# Show the occupancy as a normal list so a specific visitor can be selected
	# and removed, instead of naming them in a status line with no way to act.
	_show_rows(visitors if visitors is Array else [], "visitor")
	if count == 0:
		status.text = "Nobody is visiting your farm (%d/%d)." % [count, limit]
	else:
		status.text = "%d/%d visiting. Select one to remove." % [count, limit]
	_actions()


func _show_rows(rows: Array, kind: String) -> void:
	# Swap the list contents without going through the view loader, which would
	# refetch friends and throw the selection away.
	_revision += 1
	_loading = false
	_people_kind = kind
	_rows = rows
	people.clear()
	for row in rows:
		people.add_item(str(row.get("username", "Player")))
	_actions()


func _remove_visitor() -> void:
	if _acting:
		return
	var row := _selected()
	if row.is_empty():
		return
	_acting = true
	_actions()
	var response: Dictionary = await APIClient.remove_farm_visitor(int(row["visit_session_id"]))
	_acting = false
	if response.get("stale", false):
		return
	status.text = "Visitor removed." if bool(response.get("ok", false)) else APIClient.error_text(response)
	await _farm_visitors()


func _leave_farm() -> void:
	if _acting:
		return
	_acting = true
	_actions()
	var response: Dictionary = await APIClient.leave_farm()
	_acting = false
	if response.get("stale", false):
		return
	if bool(response.get("ok", false)):
		# Re-read the session first: the socket may only be told where to go back
		# to once this client knows it is no longer visiting.
		GameState.apply_session(await _visit_session())
		# Move the socket back before anything is redrawn, so the host's farm is
		# never left showing our avatar in it.
		APIClient.realtime.restore_own_world()
		await GameState.refresh_gameplay()
		status.text = "You are back on your own farm."
	else:
		status.text = APIClient.error_text(response)
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
