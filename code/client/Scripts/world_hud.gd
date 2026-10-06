extends CanvasLayer

var active := ""
var _switching := false
var _inventory_rows: Array = []
var _inventory_snapshot := ""
var _inventory_busy := false
var _notices: Array = []
var _notice_busy := false
var _cursor: Variant = null
var _selected_notice := 0
var _notice_unread := 0
var _request_count := 0
var _chat_unread := 0
var _inventory_selection := ""
var _toast_version := 0
var _error_version := 0


func _ready() -> void:
	for label in [%Balance, %ProgressText, %WorldLabel, %Capacity, %ItemDetails, %NoticeDetails, %Status, %LevelToastText]:
		WoodPanel.apply_status_label(label)
	%Balance.add_theme_font_size_override("font_size", 18)
	%ProgressText.add_theme_font_size_override("font_size", 16)
	%WorldLabel.add_theme_font_size_override("font_size", 16)
	%ToastClose.pressed.connect(func() -> void: %LevelToast.hide())
	WoodPanel.apply_panel_title_style(%Heading)
	for control in [%Items, %Inbox, %Category]:
		control.add_theme_font_override("font", WoodPanel.PIXEL_FONT)
		control.add_theme_font_size_override("font_size", 18)
		control.add_theme_color_override("font_color", WoodPanel.TEXT_COLOR)
	%Items.add_theme_stylebox_override("selected", WoodPanel.make_wood_card_selected_style())
	%Items.add_theme_stylebox_override("selected_focus", WoodPanel.make_wood_card_selected_style())
	for pair in [[%SocialButton, "social"], [%NoticeButton, "notifications"], [%BagButton, "inventory"], [%StoreButton, "store"], [%SettingsButton, "settings"]]:
		var button: Button = pair[0]
		var kind: String = pair[1]
		button.pressed.connect(func() -> void: switch_panel(kind))
		button.draw.connect(_draw_icon.bind(button, kind))
	%Outside.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			switch_panel("")
			get_viewport().set_input_as_handled()
	)
	%Settings.closed.connect(func() -> void:
		active = ""
		%Outside.hide()
		GameState.social_open = false
	)
	%SocialPanel.set_open(false)
	%SocialPanel.attention_changed.connect(func(count: int) -> void:
		_chat_unread = count
		%SocialButton.queue_redraw()
	)
	%Category.item_selected.connect(func(_index: int) -> void: _render_inventory(true))
	%Items.item_selected.connect(_select_item)
	%InventoryRefresh.pressed.connect(_refresh_inventory)
	%Inbox.item_selected.connect(_view_notice)
	%Dismiss.pressed.connect(func() -> void: _update_notice(true))
	%More.pressed.connect(func() -> void: refresh_notifications(true))
	%NoticeRefresh.pressed.connect(func() -> void: refresh_notifications())
	GameState.inventory_updated.connect(func(_items: Array) -> void: _render_inventory())
	GameState.economy_updated.connect(func(_data: Dictionary) -> void: _counters())
	GameState.experience_updated.connect(func(_data: Dictionary) -> void: _counters())
	GameState.level_advanced.connect(_show_level_up)
	GameState.backend_error.connect(_show_action_error)
	WoodPanel.apply_error_label(%ActionError)
	GameState.world_updated.connect(func(data: Dictionary) -> void:
		_world_label()
	)
	GameState.read_only_changed.connect(func(_value: bool) -> void: _world_label())
	GameState.session_updated.connect(func(_session: Dictionary) -> void: _world_label())
	# Being dropped from a visit changes which world every read must come from,
	# so the reload is triggered by the event rather than waiting for the poll.
	APIClient.realtime.visit_ended.connect(_visit_ended)
	APIClient.realtime.room_changed.connect(func(_room: String) -> void: GameState.refresh_gameplay())
	Global.session_changed.connect(_clear_account)
	GameState.store_requested.connect(func() -> void: switch_panel("store"))
	get_viewport().size_changed.connect(_resize)
	_resize()
	_counters()
	_render_inventory(true)
	_world_label()
	var timer := Timer.new()
	timer.wait_time = 20.0
	timer.timeout.connect(_refresh_badges)
	add_child(timer)
	timer.start()
	_refresh_badges()


func _world_label() -> void:
	var state := "%s · %s" % [
		str(GameState.world_state.get("current_season", "")).capitalize(),
		str(GameState.world_state.get("weather", "")).capitalize(),
	]
	# While visiting, the world state on screen belongs to the host, so the label
	# has to say so or the player reads another player's farm as their own.
	%WorldLabel.text = ("Visiting · read-only · " + state) if GameState.read_only else state


func _visit_ended(message: String) -> void:
	_show_action_error(message)
	_world_label()
	# The session on this client still describes the visit that was just taken
	# away, so the authoritative one is fetched before anything else reads it.
	GameState.refresh_gameplay()


func _resize() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	%PanelArea.offset_left = -minf(640.0, viewport_size.x - 16.0)
	%PanelArea.anchor_bottom = 0.0
	%PanelArea.offset_bottom = minf(730.0, viewport_size.y - 24.0)
	%Items.max_columns = maxi(1, int((minf(640.0, viewport_size.x - 16.0) - 90.0) / 120.0))


func switch_panel(kind: String) -> void:
	if _switching or GameState.menu_open:
		return
	_switching = true
	var next := "" if kind == active else kind
	if active == "settings" and not await %Settings.request_close():
		_switching = false
		return
	%SocialPanel.set_open(false)
	active = next
	%Outside.visible = active != ""
	%PanelArea.visible = active in ["social", "inventory", "notifications", "store"]
	%SocialPanel.visible = active == "social"
	%Inventory.visible = active == "inventory"
	%Notifications.visible = active == "notifications"
	%Store.visible = active == "store"
	%Status.text = ""
	%Heading.text = active.capitalize()
	GameState.social_open = active != ""
	match active:
		"social": %SocialPanel.set_open(true)
		"inventory": _refresh_inventory()
		"notifications": refresh_notifications()
		"settings": %Settings.show_overlay()
		"store": %Store.open_store()
	_switching = false


func _input(event: InputEvent) -> void:
	if active != "" and event.is_action_pressed("ui_cancel"):
		switch_panel("")
		get_viewport().set_input_as_handled()


func _counters() -> void:
	var xp: Dictionary = GameState.experience
	var level := int(xp.get("level", 1))
	var maximum := bool(xp.get("max_level", false))
	%Balance.text = "Aura %d\nLevel %d — %s" % [int(GameState.economy.get("aura_balance", 0)), level, xp.get("title", "Villager")]
	%ProgressText.text = "Max level" if maximum else "%d / %d XP toward Level %d" % [int(xp.get("current_xp", 0)), int(xp.get("xp_span", 0)), level + 1]
	%XP.max_value = 1.0 if maximum else maxf(1.0, float(xp.get("xp_span", 1)))
	%XP.value = 1.0 if maximum else float(xp.get("current_xp", 0))
	%XP.tooltip_text = "Total XP: %d" % int(xp.get("total_xp", 0))
	%ProgressText.tooltip_text = %XP.tooltip_text


func _show_level_up(previous: Dictionary, current: Dictionary) -> void:
	var old_level := int(previous.get("level", 1))
	var level := int(current.get("level", 1))
	var gained_slots := int(current.get("slot_increment", 0)) - int(previous.get("slot_increment", 0))
	var aura := 0
	for reward in current.get("rewards", []):
		if int(reward["level"]) > old_level and int(reward["level"]) <= level:
			aura += int(reward.get("aura", 0))
	var lines := PackedStringArray(["Level %d — %s" % [level, current.get("title", "")]])
	if gained_slots > 0:
		lines.append("+%d inventory slots" % gained_slots)
	if aura > 0:
		lines.append("+%d Aura awarded" % aura)
	var unlocked := PackedStringArray()
	for item in current.get("unlocked_items", []):
		if int(item.get("required_level", 1)) > old_level:
			unlocked.append(str(item["name"]))
	if not unlocked.is_empty():
		var preview := ", ".join(unlocked.slice(0, 3))
		lines.append("Store unlocked: " + preview + (" (+%d more)" % (unlocked.size() - 3) if unlocked.size() > 3 else ""))
	%LevelToastText.text = "\n".join(lines)
	%LevelToastText.tooltip_text = ", ".join(unlocked)
	%LevelToast.show()
	_toast_version += 1
	var version := _toast_version
	await get_tree().create_timer(9.0).timeout
	if version == _toast_version:
		%LevelToast.hide()


func _show_action_error(message: String) -> void:
	%ActionError.text = message
	%ActionError.show()
	_error_version += 1
	var version := _error_version
	await get_tree().create_timer(8.0).timeout
	if version == _error_version:
		%ActionError.hide()


func _refresh_inventory() -> void:
	if _inventory_busy:
		return
	_inventory_busy = true
	%InventoryRefresh.disabled = true
	%Status.text = "Loading inventory..."
	var response: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_GET, "/inventory/")
	_inventory_busy = false
	%InventoryRefresh.disabled = false
	if response.get("stale", false):
		return
	if response.get("ok", false):
		GameState._apply_data("inventory", APIClient.data_of(response))
		%Status.text = "" if not GameState.inventory.is_empty() else "Your inventory is empty."
	else:
		%Status.text = APIClient.error_text(response)


func _render_inventory(force := false) -> void:
	var snapshot := JSON.stringify(GameState.inventory_summary)
	if not force and snapshot == _inventory_snapshot:
		return
	_inventory_snapshot = snapshot
	var scroll: float = %Items.get_v_scroll_bar().value
	var category := "All" if %Category.item_count == 0 else str(%Category.get_item_metadata(%Category.selected))
	%Category.clear()
	for name in ["All", "seeds", "crops", "fish", "rare_materials", "tools", "houses", "Other"]:
		%Category.add_item("Materials" if name == "rare_materials" else ("Placeables" if name == "houses" else str(name).capitalize()))
		%Category.set_item_metadata(%Category.item_count - 1, name)
		if name == category:
			%Category.select(%Category.item_count - 1)
	if %Category.selected < 0:
		%Category.select(0)
	_inventory_rows.clear()
	%Items.clear()
	for row in GameState.inventory:
		var partition: String = str(row.get("partition") if row.get("partition") != null else "Other")
		if category != "All" and partition != category:
			continue
		_inventory_rows.append(row)
		var item: Dictionary = row.get("item", {})
		var index: int = %Items.add_item("%s\n×%d" % [item.get("name", row["item_code"]), row["quantity"]], WoodPanel.item_icon(row["item_code"]))
		%Items.set_item_tooltip(index, _item_details(row))
		if str(row["id"]) == _inventory_selection:
			%Items.select(index)
	%ItemDetails.text = "No items in this category." if _inventory_rows.is_empty() else "Select an item for details."
	var counts := {}
	for stack in GameState.inventory:
		var partition := str(stack.get("partition", "Other"))
		counts[partition] = int(counts.get(partition, 0)) + 1
	var capacity := int(GameState.inventory_summary.get("capacity", 0))
	%Capacity.text = "%d / %d slots occupied · %d items" % [int(GameState.inventory_summary.get("used_slots", 0)), capacity, int(GameState.inventory_summary.get("total_quantity", 0))]
	%Capacity.tooltip_text = "One shared inventory: %d preserved base + %d level slots." % [int(GameState.inventory_summary.get("base_capacity", 0)), int(GameState.inventory_summary.get("level_slots", 0))]
	if counts.has(category):
		%Capacity.text += "\nShowing %d stacks in this category" % int(counts[category])
	if not %Items.get_selected_items().is_empty():
		_select_item(%Items.get_selected_items()[0])
	%Items.get_v_scroll_bar().set_deferred("value", scroll)


func _item_details(row: Dictionary) -> String:
	var item: Dictionary = row.get("item", {})
	return "%s ×%d\n%s\n%s · %s · Maximum stack %d" % [item.get("name", row["item_code"]), row["quantity"], item.get("description", "") if item.get("description") != null else "", item.get("category", ""), item.get("rarity", ""), int(item.get("max_stack", 0))]


func _select_item(index: int) -> void:
	_inventory_selection = str(_inventory_rows[index]["id"])
	%ItemDetails.text = _item_details(_inventory_rows[index])


func _refresh_badges() -> void:
	if not Global.is_logged_in():
		return
	# One bounded inbox refresh; counters share GameState's gameplay refresh.
	await refresh_notifications()
	var response: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_GET, "/social/requests")
	if response.get("ok", false) and not response.get("stale", false):
		_request_count = 0
		for row in APIClient.data_of(response):
			if int(row.get("requested_by", 0)) != Global.player_id:
				_request_count += 1
		%SocialButton.queue_redraw()


func refresh_notifications(older := false) -> void:
	if _notice_busy or (older and _cursor == null):
		return
	_notice_busy = true
	if active == "notifications":
		%Status.text = "Loading notifications..."
	var path := "/notifications?limit=30" + ("&before=%d" % int(_cursor) if older else "")
	var response: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_GET, path)
	_notice_busy = false
	if response.get("stale", false):
		return
	if not response.get("ok", false):
		if active == "notifications":
			%Status.text = APIClient.error_text(response)
		return
	var data: Dictionary = APIClient.data_of(response)
	if older:
		_notices.append_array(data.get("items", []))
		_cursor = data.get("next_cursor")
	else:
		# Preserve already loaded older pages while merging the authoritative first page.
		var fresh: Array = data.get("items", [])
		var ids := {}
		for item in fresh:
			ids[item["id"]] = true
		var oldest := int(fresh[-1]["id"]) if not fresh.is_empty() else 0
		for item in _notices:
			if int(item["id"]) < oldest and not ids.has(item["id"]):
				fresh.append(item)
		if _notices.size() <= 30:
			_cursor = data.get("next_cursor")
		_notices = fresh
	_notice_unread = int(data.get("unread_count", 0))
	_render_notices()
	if active == "notifications":
		%Status.text = "No notifications yet." if _notices.is_empty() else "Select a message to read it."


func _render_notices() -> void:
	%Inbox.clear()
	%Dismiss.disabled = true
	for notice in _notices:
		var index: int = %Inbox.add_item(("• " if not notice.get("is_read", false) else "") + str(notice["message"]))
		%Inbox.set_item_tooltip(index, str(notice.get("created_at", "")))
		if int(notice["id"]) == _selected_notice:
			%Inbox.select(index)
			%Dismiss.disabled = false
	%More.disabled = _cursor == null
	%NoticeButton.queue_redraw()


func _view_notice(index: int) -> void:
	var notice: Dictionary = _notices[index]
	_selected_notice = int(notice["id"])
	%NoticeDetails.text = str(notice["message"]) + "\n" + str(notice.get("created_at", ""))
	%Dismiss.disabled = false
	if not notice.get("is_read", false):
		await _update_notice(false)


func _update_notice(dismiss: bool) -> void:
	if _selected_notice == 0:
		return
	var id := _selected_notice
	var response: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_POST, "/notifications/%d" % id, {"dismiss": dismiss})
	if response.get("stale", false):
		return
	if not response.get("ok", false):
		%Status.text = APIClient.error_text(response)
		return
	for item in _notices:
		if int(item["id"]) == id:
			if not item.get("is_read", false):
				_notice_unread = maxi(0, _notice_unread - 1)
			item["is_read"] = true
	if dismiss:
		_notices = _notices.filter(func(item: Dictionary) -> bool: return int(item["id"]) != id)
		_selected_notice = 0
		%NoticeDetails.text = "Notification dismissed."
	_render_notices()
	await refresh_notifications()


func _clear_account() -> void:
	_toast_version += 1
	_error_version += 1
	%LevelToast.hide()
	%ActionError.hide()
	_notices.clear()
	_inventory_rows.clear()
	_inventory_snapshot = ""
	_inventory_selection = ""
	_cursor = null
	_selected_notice = 0
	_notice_unread = 0
	_request_count = 0
	_chat_unread = 0
	%NoticeDetails.text = ""
	%ItemDetails.text = ""
	%Status.text = ""
	%Items.clear()
	_render_notices()
	%SocialButton.queue_redraw()
	active = ""
	%Settings.hide()
	%PanelArea.hide()
	%Outside.hide()
	%SocialPanel.set_open(false)
	GameState.social_open = false
	_world_label()


func _draw_icon(button: Button, kind: String) -> void:
	var c := button.size / 2.0
	var ink := WoodPanel.TEXT_COLOR
	match kind:
		"social":
			button.draw_arc(c, 13, 0, TAU, 32, ink, 2)
			button.draw_line(c + Vector2(-13, 0), c + Vector2(13, 0), ink, 2)
			button.draw_arc(c, 7, 0, TAU, 24, ink, 2)
			button.draw_line(c + Vector2(0, -13), c + Vector2(0, 13), ink, 2)
		"notifications":
			button.draw_arc(c, 10, PI, TAU, 20, ink, 2)
			button.draw_line(c + Vector2(-10, 0), c + Vector2(-12, 9), ink, 2)
			button.draw_line(c + Vector2(10, 0), c + Vector2(12, 9), ink, 2)
			button.draw_line(c + Vector2(-12, 9), c + Vector2(12, 9), ink, 2)
			button.draw_circle(c + Vector2(0, 12), 2, ink)
		"inventory":
			button.draw_rect(Rect2(c - Vector2(12, 7), Vector2(24, 20)), ink, false, 2)
			button.draw_arc(c - Vector2(0, 7), 6, PI, TAU, 12, ink, 2)
		"settings":
			button.draw_arc(c, 9, 0, TAU, 20, ink, 2)
			button.draw_circle(c, 3, ink)
			for i in 8:
				var direction := Vector2.RIGHT.rotated(i * TAU / 8)
				button.draw_line(c + direction * 9, c + direction * 14, ink, 3)
		"store":
			button.draw_rect(Rect2(c + Vector2(-12, -3), Vector2(24, 17)), ink, false, 2)
			button.draw_line(c + Vector2(-15, -4), c + Vector2(15, -4), ink, 3)
			button.draw_line(c + Vector2(-15, -4), c + Vector2(-10, -12), ink, 2)
			button.draw_line(c + Vector2(-10, -12), c + Vector2(10, -12), ink, 2)
			button.draw_line(c + Vector2(10, -12), c + Vector2(15, -4), ink, 2)
			button.draw_rect(Rect2(c + Vector2(-3, 3), Vector2(7, 11)), ink, false, 2)
	var count := _notice_unread if kind == "notifications" else (_request_count + _chat_unread if kind == "social" else 0)
	if count > 0:
		var corner := Vector2(button.size.x - 12, 12)
		button.draw_circle(corner, 10, Color(0.65, 0.18, 0.12))
		button.draw_string(WoodPanel.PIXEL_FONT, corner + Vector2(-10, 4), str(mini(count, 99)), HORIZONTAL_ALIGNMENT_CENTER, 20, 12, Color.WHITE)
