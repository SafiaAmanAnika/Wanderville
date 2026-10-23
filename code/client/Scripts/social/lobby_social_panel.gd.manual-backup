extends "res://Scripts/social_panel.gd"
## Lobby adapter for the existing social UI and authenticated API actions.

const Style := preload("res://Scripts/ui/lobby_theme.gd")
const Avatar := preload("res://Scripts/customization/character_preview.gd")
var _cards: VBoxContainer
var _profile_column: VBoxContainer
var _profile_name: Label
var _profile_state: Label
var _profile_picture: Control
var _profile_help: Label

const SECTION_BY_VIEW := ["friends", "requests", "search", "blocked", "invitations"]

var _poll_elapsed := 0.0
var _polling := false
var _conversation_title: Label


func _ready() -> void:
	super._ready()
	mode.set_item_disabled(0, true)
	mode.select(1)
	_build_people_cards()
	_conversation_title = Style.label("Choose a friend to start a conversation", 24)
	_conversation_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chat.add_child(_conversation_title)
	chat.move_child(_conversation_title, 0)
	history.custom_minimum_size.y = 250
	history.size_flags_vertical = Control.SIZE_EXPAND_FILL
	message.placeholder_text = "Write a private message…"
	Style.apply_tree.call_deferred(self)
	set_open(false)


func open_people(index: int) -> void:
	show_section(SECTION_BY_VIEW[index] if index >= 0 and index < SECTION_BY_VIEW.size() else "friends")


func show_section(section_name: String) -> void:
	# Do not leave another section's results/actions visible during its request.
	_rows.clear()
	people.clear()
	_actions()
	super.show_section(section_name)
	%SearchRow.visible = section_name == "search"


func set_open(value: bool) -> void:
	# Discard replies belonging to an earlier open/close or account session.
	_revision += 1
	_loading = false
	super.set_open(value)


func _unhandled_key_input(_event: InputEvent) -> void:
	# The lobby modal owns Escape, including the focused search field.
	pass


func _connection(_connected: bool) -> void:
	# Lobby services use HTTP; campus WebSocket status is unrelated here.
	pass


func _process(delta: float) -> void:
	super._process(delta)
	_conversation_title.text = "Message · " + str(_names.get(_target, "Friend")) if _target > 0 else "Choose a friend to start a conversation"
	message.editable = _target > 0 and Global.is_logged_in()
	%Send.disabled = _sending or not message.editable or message.text.strip_edges().is_empty()
	# The campus socket intentionally stops outside world.tscn. Reuse the same
	# message endpoint for this panel instead of inventing lobby presence.
	if not visible or not chat.visible or mode.selected != 1 or _target <= 0:
		return
	_poll_elapsed += delta
	if _poll_elapsed < 3.0 or _polling:
		return
	_poll_elapsed = 0.0
	_poll_messages()


func _poll_messages() -> void:
	_polling = true
	var target := _target
	var revision := _revision
	var records: Array = _private.get(target, [])
	var after := int(records[-1]["id"]) if not records.is_empty() else 0
	var response: Dictionary = await APIClient.get_direct_messages(target, after)
	_polling = false
	if revision != _revision or response.get("stale", false) or not visible:
		return
	if not response.get("ok", false):
		status.text = APIClient.error_text(response)
		return
	for record in APIClient.data_of(response):
		_direct_message(record)
	status.text = "No messages yet." if _private.get(target, []).is_empty() else "Private conversation."


func _build_people_cards() -> void:
	people.hide()
	var layout := HBoxContainer.new()
	layout.name = "PeopleCards"
	layout.add_theme_constant_override("separation", 18)
	friends.add_child(layout)
	friends.move_child(layout, people.get_index())
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(380, 300)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	_cards = VBoxContainer.new()
	_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards.add_theme_constant_override("separation", 6)
	scroll.add_child(_cards)
	var detail := PanelContainer.new()
	detail.custom_minimum_size.x = 260
	detail.add_theme_stylebox_override("panel", Style.box(Color("fff0d9"), 14))
	layout.add_child(detail)
	_profile_column = VBoxContainer.new()
	detail.add_child(_profile_column)
	_profile_picture = Control.new()
	_profile_picture.custom_minimum_size = Vector2(220, 145)
	_profile_column.add_child(_profile_picture)
	_profile_name = Style.label("Choose a player", 25)
	_profile_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_profile_column.add_child(_profile_name)
	_profile_state = Style.label("", 19)
	_profile_column.add_child(_profile_state)
	_profile_help = Style.label("Select a player to see the available actions.", 17)
	_profile_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_profile_column.add_child(_profile_help)
	var actions := %Primary.get_parent()
	actions.reparent(_profile_column)

func _actions() -> void:
	super._actions()
	if _cards != null: _render_people_cards()

func _render_people_cards() -> void:
	for child in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()
	for i in _rows.size():
		var row: Dictionary = _rows[i]
		var name := str(row.get("username", row.get("host_username", "Player")))
		var button := Style.button("")
		button.custom_minimum_size = Vector2(360, 78)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var selected := people.get_selected_items()
		if not selected.is_empty() and selected[0] == i: button.add_theme_stylebox_override("normal", Style.box(Color("e9c9a1"), 8))
		var line := HBoxContainer.new()
		line.name = "Row"
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		line.offset_left = 8
		line.offset_right = -8
		line.offset_top = 6
		line.offset_bottom = -6
		button.add_child(line)
		var picture := Control.new()
		picture.custom_minimum_size = Vector2(44, 62)
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(picture)
		_add_avatar(picture, row, false)
		var words := VBoxContainer.new()
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(words)
		var caption := Style.label(name, 21)
		caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		words.add_child(caption)
		var state := "Online" if row.get("online", false) else "Offline"
		if view.selected == 1: state = "Sent request" if int(row.get("requested_by", 0)) == Global.player_id else "Incoming request"
		if view.selected == 4: state = str(row.get("world_name", "Farm invitation"))
		var detail := Style.label(state, 17)
		detail.modulate = Style.SAGE if row.get("online", false) else Color("8b735e")
		detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		words.add_child(detail)
		button.pressed.connect(func(): people.select(i); _actions())
		_cards.add_child(button)
		var action_text := "Remove visitor" if _people_kind == "visitor" else "Message" if view.selected == 0 else "Cancel" if view.selected == 1 and int(row.get("requested_by", 0)) == Global.player_id else "Accept" if view.selected == 1 else "Visit farm" if view.selected == 4 else "Add friend" if view.selected == 2 else "Unblock"
		var action := Style.button(action_text, true)
		action.name = "PrimaryAction"
		action.add_theme_font_size_override("font_size", 16)
		action.disabled = _acting
		line.add_child(action)
		action.pressed.connect(func(): people.select(i); _actions(); _primary())
	if _rows.is_empty():
		var empty := Style.label("Search for a username at reception." if _section == "search" else "No results yet.", 20)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_cards.add_child(empty)
	var selected := _selected()
	_profile_help.visible = selected.is_empty()
	_profile_name.text = str(selected.get("username", selected.get("host_username", "Choose a player")))
	_profile_state.text = "" if selected.is_empty() else "Online" if selected.get("online", false) else "Offline"
	for child in _profile_picture.get_children(): child.queue_free()
	if not selected.is_empty(): _add_avatar(_profile_picture, selected, true)

func _add_avatar(parent: Control, row: Dictionary, large: bool) -> void:
	var code := str(row.get("character_code", ""))
	if Global.CHARACTERS.has(code) and Global.CHARACTERS[code].folder != "":
		var avatar := Avatar.new()
		avatar.character = code
		avatar.position = Vector2(110, 65) if large else Vector2(22, 28)
		avatar.scale = Vector2.ONE * (0.65 if large else 0.25)
		parent.add_child(avatar)
	else:
		# The API does not always return appearance; initials avoid inventing a look.
		var initials := Style.label(str(row.get("username", row.get("host_username", "?"))).left(1).to_upper(), 44 if large else 26)
		initials.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initials.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		initials.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(initials)

func _update_nav() -> void:
	super._update_nav()
	if _nav.has("requests"): _nav.requests.text = "Requests" + (" (%d)" % _request_count if _request_count > 0 else "")
	if _nav.has("notifications"): _nav.notifications.text = "Notices" + (" (%d)" % _notice_unread if _notice_unread > 0 else "")
