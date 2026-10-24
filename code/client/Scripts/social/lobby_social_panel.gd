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
var _section_title: Label
var _request_tabs: HBoxContainer
var _request_tab := 0
var _incoming: Button
var _sent: Button
var _conversation_picker: OptionButton
var _community: Window
var _profile_detail: PanelContainer
var _farm_actions: VBoxContainer
var _profile_gift: Button


func _ready() -> void:
	super._ready()
	mode.set_item_disabled(0, true)
	mode.select(1)
	_build_people_cards()
	_build_shell()
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
	if _section_title != null:
		_section_title.text = {"friends":"Friends", "requests":"Friend Requests", "messages":"Messages", "invitations":"Farm Visits", "notifications":"Notices", "search":"Find Players", "blocked":"Blocked Players"}.get(section_name, "Social")
		_request_tabs.visible = section_name == "requests"
		_profile_detail.visible = section_name != "notifications"
		_farm_actions.visible = section_name == "invitations"
	if section_name == "messages": _load_conversations()
	if _cards != null: _render_people_cards()


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
	_profile_detail = detail
	detail.add_theme_stylebox_override("panel", Style.box(Color("fff0d9"), 14))
	layout.add_child(detail)
	detail.owner = self
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
	if _cards != null:
		_render_people_cards()


func _render_people_cards() -> void:
	if _cards == null:
		return

	# Remove previous visual cards.
	# The hidden ItemList remains the source of selection state.
	for child in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()

	var selected_items := people.get_selected_items()
	var incoming_count := 0
	var sent_count := 0
	for record in _rows:
		if int(record.get("requested_by", 0)) == Global.player_id: sent_count += 1
		else: incoming_count += 1
	if _incoming != null:
		_incoming.text = "Incoming · %d" % incoming_count
		_sent.text = "Sent · %d" % sent_count

	for i in range(_rows.size()):
		var row: Dictionary = _rows[i]
		if view.selected == 1 and (int(row.get("requested_by", 0)) == Global.player_id) != (_request_tab == 1): continue
		var name := str(
			row.get(
				"username",
				row.get("host_username", "Player")
			)
		)

		var is_selected := (
			not selected_items.is_empty()
			and selected_items[0] == i
		)

		# The card is a container, NOT a Button.
		# Select / Accept / Decline are independent buttons.
		var card := PanelContainer.new()
		card.name = "PlayerCard_%d" % i
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var bg := Color("e9c9a1") if is_selected else Color("fff0d9")
		card.add_theme_stylebox_override(
			"panel",
			Style.box(bg, 10)
		)

		_cards.add_child(card)

		var content := VBoxContainer.new()
		content.name = "Content"
		content.add_theme_constant_override("separation", 5)
		card.add_child(content)

		# Player selection button.
		var select_button := Style.button("")
		select_button.name = "SelectPlayer"
		select_button.custom_minimum_size = Vector2(300, 76)
		select_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.add_child(select_button)

		var line := HBoxContainer.new()
		line.name = "Row"
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_constant_override("separation", 12)
		select_button.add_child(line)

		line.set_anchors_and_offsets_preset(
			Control.PRESET_FULL_RECT
		)
		line.offset_left = 8
		line.offset_right = -8
		line.offset_top = 6
		line.offset_bottom = -6

		# Character preview.
		var picture := Control.new()
		picture.custom_minimum_size = Vector2(44, 62)
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(picture)

		_add_avatar(picture, row, false)

		# Username and current relationship state.
		var words := VBoxContainer.new()
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(words)

		var caption := Style.label(name, 21)
		caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		words.add_child(caption)

		var state := "Online" if row.get("online", false) else "Offline"

		if view.selected == 1:
			state = (
				"Sent request"
				if int(row.get("requested_by", 0)) == Global.player_id
				else "Incoming request"
			)
		elif view.selected == VIEW_INVITATIONS:
			state = str(row.get("world_name", "Farm invitation"))

		var detail := Style.label(state, 17)
		detail.modulate = (
			Style.SAGE if row.get("online", false)
			else Color("8b735e")
		)
		detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		words.add_child(detail)

		select_button.pressed.connect(
			_on_card_selected.bind(i)
		)

		# Separate action row.
		var buttons := HBoxContainer.new()
		buttons.name = "Buttons"
		buttons.add_theme_constant_override("separation", 8)
		content.add_child(buttons)

		var primary_button := Style.button(
			_card_primary_label(row),
			true
		)
		primary_button.name = "PrimaryAction"
		primary_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		primary_button.add_theme_font_size_override("font_size", 16)
		primary_button.disabled = _acting

		buttons.add_child(primary_button)

		primary_button.pressed.connect(
			_on_card_primary.bind(i)
		)

		# Only recipients may decline a pending friend request.
		# Farm invitations shown here are incoming invitations.
		var incoming_request := (
			view.selected == 1
			and int(row.get("requested_by", 0)) != Global.player_id
		)

		var can_decline := (
			_people_kind != "visitor"
			and (
				incoming_request
				or view.selected == VIEW_INVITATIONS
			)
		)

		if can_decline:
			var decline_button := Style.button("Decline")
			decline_button.name = "DeclineAction"
			decline_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			decline_button.add_theme_font_size_override("font_size", 16)
			decline_button.disabled = _acting

			buttons.add_child(decline_button)

			decline_button.pressed.connect(
				_on_card_decline.bind(i)
			)

	# Empty state.
	if _cards.get_child_count() == 0:
		var text := (
			"Search for a username at reception."
			if _section == "search"
			else "No results yet."
		)
		var empty := Style.label(text, 20)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_cards.add_child(empty)

	# Keep the existing right-side player profile.
	var selected := _selected()

	_profile_help.visible = selected.is_empty()

	_profile_name.text = str(
		selected.get(
			"username",
			selected.get("host_username", "Choose a player")
		)
	)

	if selected.is_empty():
		_profile_state.text = ""
	elif _people_kind == "visitor":
		_profile_state.text = "Farm visitor"
	elif view.selected == 1:
		_profile_state.text = (
			"Sent request" if int(selected.get("requested_by", 0)) == Global.player_id
			else "Incoming request"
		)
	elif view.selected == VIEW_INVITATIONS:
		_profile_state.text = "Farm invitation"
	else:
		_profile_state.text = "Online" if selected.get("online", false) else "Offline"
	if selected.has("level"): _profile_state.text += "\nLevel %d · %s" % [int(selected.level), str(selected.get("title", "Wanderer"))]

	for child in _profile_picture.get_children():
		child.queue_free()

	if not selected.is_empty():
		_add_avatar(_profile_picture, selected, true)
	if _section == "messages":
		_profile_name.text = str(_names.get(_target, "Choose a conversation"))
		_profile_state.text = "Private conversation" if _target > 0 else ""
		%Primary.get_parent().hide()
	else:
		%Primary.get_parent().visible = view.selected not in [1, VIEW_INVITATIONS]
	if _profile_gift != null: _profile_gift.visible = _section == "friends" and not selected.is_empty()

func _build_shell() -> void:
	var shell := HBoxContainer.new(); shell.name = "SocialColumns"; shell.add_theme_constant_override("separation", 16); shell.size_flags_vertical = Control.SIZE_EXPAND_FILL; add_child(shell)
	var sidebar := VBoxContainer.new(); sidebar.name = "Navigation"; sidebar.custom_minimum_size.x = 170; sidebar.add_theme_constant_override("separation", 8); shell.add_child(sidebar)
	sidebar.add_child(Style.label("SOCIAL", 17))
	for key in _nav:
		var button: Button = _nav[key]; button.reparent(sidebar); button.script = null; button.theme = Style.theme(); button.alignment = HORIZONTAL_ALIGNMENT_LEFT; button.custom_minimum_size.y = 44
	_nav.invitations.text = "Farm Visits"; _nav.notifications.text = "Notices"
	var find := Style.button("Find Players"); sidebar.add_child(find); find.pressed.connect(func(): show_section("search"))
	var spacer := Control.new(); spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL; sidebar.add_child(spacer)
	var blocked := Style.button("Blocked Players"); sidebar.add_child(blocked); blocked.pressed.connect(func(): show_section("blocked"))
	_community = preload("res://Scripts/social/community_window.gd").new(); add_child(_community)
	var gifts := Style.button("Gifts / Wishlist"); sidebar.add_child(gifts); gifts.pressed.connect(func(): _community.open_for())
	var middle := VBoxContainer.new(); middle.name = "SectionContent"; middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL; middle.size_flags_vertical = Control.SIZE_EXPAND_FILL; shell.add_child(middle)
	var toolbar := HBoxContainer.new(); middle.add_child(toolbar)
	_section_title = Style.label("Friends", 25); _section_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; toolbar.add_child(_section_title)
	var refresh := Style.button("Refresh"); toolbar.add_child(refresh); refresh.pressed.connect(func():
		if _acting or _loading: return
		if _section == "notifications": refresh_notifications()
		elif _section == "messages": _poll_messages()
		else: _load_people()
	)
	_request_tabs = HBoxContainer.new(); middle.add_child(_request_tabs); _request_tabs.hide()
	var group := ButtonGroup.new()
	_incoming = Style.button("Incoming"); _sent = Style.button("Sent")
	for button in [_incoming, _sent]: button.toggle_mode = true; button.button_group = group; _request_tabs.add_child(button)
	_incoming.button_pressed = true
	_incoming.pressed.connect(func(): _request_tab = 0; people.deselect_all(); _actions())
	_sent.pressed.connect(func(): _request_tab = 1; people.deselect_all(); _actions())
	_farm_actions = VBoxContainer.new(); middle.add_child(_farm_actions); _farm_actions.hide()
	var visit_state := Style.label("Visiting a farm · read-only" if GameState.read_only else "Your farm · manage invitations and visitors", 16)
	visit_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; _farm_actions.add_child(visit_state)
	var visit_button := Style.button("Leave Farm" if GameState.read_only else "Current Visitors"); _farm_actions.add_child(visit_button)
	visit_button.pressed.connect(func():
		if GameState.read_only: _leave_farm()
		else: _farm_visitors()
	)
	panel.reparent(middle); panel.size_flags_vertical = Control.SIZE_EXPAND_FILL; panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL; panel.script = null
	_profile_detail.reparent(shell); _profile_detail.custom_minimum_size.x = 270
	_profile_column.add_child(Style.label("PLAYER DETAILS", 16)); _profile_column.move_child(_profile_column.get_child(-1), 0)
	var profile_gift := Style.button("Gift / Wishlist"); _profile_column.add_child(profile_gift)
	_profile_gift = profile_gift
	profile_gift.pressed.connect(func():
		var selected := _selected()
		if not selected.is_empty(): _community.open_for(int(selected.get("id", 0)))
	)
	$Dock.hide()
	var layout := friends.get_node("PeopleCards")
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := layout.get_child(0) as ScrollContainer; scroll.custom_minimum_size = Vector2(340, 300); scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_conversation_picker = OptionButton.new(); _conversation_picker.name = "Conversations"; chat.add_child(_conversation_picker); chat.move_child(_conversation_picker, 0)
	_conversation_picker.item_selected.connect(func(index: int):
		_target = _conversation_picker.get_item_id(index); mode.select(1); _mode_changed(1); _poll_messages(); _actions()
	)
	mode.hide()
	custom_minimum_size = Vector2(980, 500)
	# Reparented scene controls keep their stable %Name API for the inherited
	# controller and the integration tests, including the profile action row.
	for node in find_children("*", "", true, false):
		if node.unique_name_in_owner: node.owner = self

func _load_conversations() -> void:
	var revision := _revision
	var response: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_GET, "/social/friends")
	if revision != _revision or response.get("stale", false): return
	_conversation_picker.clear()
	if not response.get("ok", false): status.text = APIClient.error_text(response); return
	for record in APIClient.data_of(response):
		var id := int(record["id"]); _names[id] = str(record["username"]); _conversation_picker.add_item(_names[id], id)
		if id == _target: _conversation_picker.select(_conversation_picker.item_count - 1)
	if _target > 0: _poll_messages()


func _card_primary_label(row: Dictionary) -> String:
	if _people_kind == "visitor":
		return "Remove visitor"

	match view.selected:
		0:
			return "Message"
		1:
			if int(row.get("requested_by", 0)) == Global.player_id:
				return "Cancel"
			return "Accept"
		2:
			return "Add friend"
		3:
			return "Unblock"
		VIEW_INVITATIONS:
			return "Accept"

	return "Select"


func _on_card_selected(index: int) -> void:
	if _acting or index < 0 or index >= _rows.size():
		return
	people.select(index)
	# Defer the redraw so the button isn't destroyed while handling its click.
	call_deferred("_actions")


func _on_card_primary(index: int) -> void:
	_queue_card_action(index, false)


func _on_card_decline(index: int) -> void:
	if _people_kind != "people":
		return
	if view.selected == 1:
		if index < 0 or index >= _rows.size():
			return
		if int((_rows[index] as Dictionary).get("requested_by", 0)) == Global.player_id:
			return
	elif view.selected != VIEW_INVITATIONS:
		return
	_queue_card_action(index, true)


func _card_row_id(row: Dictionary, kind: String) -> int:
	# Visitor rows are keyed by visit_session_id, not player id.
	return int(row.get("visit_session_id", 0)) if kind == "visitor" else int(row.get("id", 0))


func _queue_card_action(index: int, decline: bool) -> void:
	if _acting or index < 0 or index >= _rows.size():
		return
	var row: Dictionary = _rows[index]
	var target_id := _card_row_id(row, _people_kind)
	if target_id <= 0:
		status.text = "Invalid player or invitation ID."
		return
	var expected_view := view.selected
	var expected_kind := _people_kind
	# Dispatch outside the GUI signal. Capture the target's ID, not just an
	# index which could select another player after a background refresh.
	call_deferred("_perform_card_action", target_id, expected_view, expected_kind, decline)


func _perform_card_action(target_id: int, expected_view: int, expected_kind: String, decline: bool) -> void:
	if _acting or view.selected != expected_view or _people_kind != expected_kind:
		return
	for index in range(_rows.size()):
		if _card_row_id(_rows[index], expected_kind) == target_id:
			people.select(index)
			if decline:
				_decline()
			else:
				_primary()
			return
	status.text = "This request is no longer in the list. Refresh to see its current state."


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
