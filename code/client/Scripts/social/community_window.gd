extends Window
## Reusable native wishlist, gifts and privacy screen.
var target_id := 0
var _rows: Array = []
var _busy := false
var _refresh_again := false
var _view: OptionButton
var _friends: OptionButton
var _items: ItemList
var _code: OptionButton
var _catalog: Dictionary = {}
var _quantity: SpinBox
var _priority: SpinBox
var _status: Label
var _privacy: OptionButton
var _visibility: OptionButton
var _prompts: CheckBox
var _confirm: ConfirmationDialog
var _proposal: Dictionary = {}
var _revision := -1
var _previous_social := false


func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _ready() -> void:
	title = "Gifts, wishlists & privacy"
	size = Vector2i(620, 580)
	min_size = Vector2i(480, 480)
	visible = false
	close_requested.connect(_close)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)
	_view = OptionButton.new()
	for text in ["My wishlist", "Friend wishlist / Send gift", "Gift inbox"]:
		_view.add_item(text)
	box.add_child(_view)
	_view.item_selected.connect(func(_index: int) -> void: refresh())
	_friends = OptionButton.new()
	box.add_child(_friends)
	_friends.item_selected.connect(func(index: int) -> void:
		target_id = _friends.get_item_id(index)
		refresh()
	)
	_items = ItemList.new()
	_items.custom_minimum_size.y = 140
	_items.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_items)
	_items.item_selected.connect(_select)
	var row := HBoxContainer.new()
	box.add_child(row)
	_code = OptionButton.new()
	_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_code)
	_quantity = SpinBox.new()
	_quantity.min_value = 1
	_quantity.max_value = 99
	_quantity.prefix = "Qty "
	row.add_child(_quantity)
	_priority = SpinBox.new()
	_priority.max_value = 10
	_priority.prefix = "Priority "
	row.add_child(_priority)
	var actions := HBoxContainer.new()
	box.add_child(actions)
	_button(actions, "Save wish", _save)
	_button(actions, "Remove wish", _remove)
	_button(actions, "Send gift", _prepare_gift)
	_button(actions, "Claim selected", _claim)
	var recovery := HBoxContainer.new()
	box.add_child(recovery)
	_button(recovery, "Refresh", refresh)
	_button(recovery, "Recover pending gift", _recover)
	_privacy = OptionButton.new()
	for text in ["Voice: Off", "Voice: Friends", "Voice: Nearby players"]:
		_privacy.add_item(text)
	box.add_child(_privacy)
	_visibility = OptionButton.new()
	_visibility.add_item("Wishlist: Private")
	_visibility.add_item("Wishlist: Friends")
	box.add_child(_visibility)
	_prompts = CheckBox.new()
	_prompts.text = "Show nearby friend prompts"
	box.add_child(_prompts)
	_button(box, "Save privacy", _save_preferences)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	preload("res://Scripts/ui/loading_progress.gd").attach(_status)
	_confirm = ConfirmationDialog.new()
	add_child(_confirm)
	_confirm.confirmed.connect(_send_gift)
	APIClient.realtime.snapshot_received.connect(func(data: Dictionary) -> void:
		var revision := int(data.get("social_revision", -1))
		if revision != _revision:
			_revision = revision
			if visible and not _busy:
				refresh()
	)
	Global.session_changed.connect(_close)
	preload("res://Scripts/ui/lobby_theme.gd").apply_tree(self)


func open_for(player_id: int = 0) -> void:
	_previous_social = GameState.social_open
	GameState.social_open = true
	target_id = player_id
	_view.select(1 if player_id > 0 else 0)
	popup_centered()
	var response: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_GET, "/social/friends")
	if not visible or response.get("stale", false):
		return
	_friends.clear()
	var found_target := false
	if response.get("ok", false):
		for friend in APIClient.data_of(response):
			_friends.add_item(str(friend["username"]), int(friend["id"]))
			if int(friend["id"]) == target_id:
				found_target = true
				_friends.select(_friends.item_count - 1)
		if target_id == 0 and _friends.item_count > 0:
			target_id = _friends.get_item_id(0)
	if player_id > 0 and not found_target:
		target_id = 0
		_friends.select(-1)
	response = await APIClient.authenticated(HTTPClient.METHOD_GET, "/social/preferences")
	if response.get("ok", false) and not response.get("stale", false):
		var data: Dictionary = APIClient.data_of(response)
		_privacy.select(["off", "friends", "nearby"].find(str(data["voice_privacy"])))
		_visibility.select(1 if data["wishlist_visibility"] == "friends" else 0)
		_prompts.button_pressed = data["proximity_prompts"]
	if _code.item_count == 0:
		response = await APIClient.authenticated(HTTPClient.METHOD_GET, "/inventory/catalog")
		if response.get("ok", false) and not response.get("stale", false):
			for item in APIClient.data_of(response):
				_catalog[str(item["item_code"])] = str(item["name"])
				if item["giftable"]:
					_code.add_item(str(item["name"]))
					_code.set_item_metadata(_code.item_count - 1, str(item["item_code"]))
	await refresh()


func item_code() -> String:
	return str(_code.get_item_metadata(_code.selected)) if _code.selected >= 0 else ""


func select_code(code: String) -> void:
	for i in _code.item_count:
		if str(_code.get_item_metadata(i)) == code:
			_code.select(i)
			return


func _close() -> void:
	hide()
	_confirm.hide()
	_proposal.clear()
	GameState.social_open = _previous_social if Global.is_logged_in() else false


func _result(response: Dictionary) -> bool:
	if response.get("stale", false):
		return false
	_status.text = "Saved." if response.get("ok", false) else APIClient.error_text(response)
	return response.get("ok", false)


func _process(_delta: float) -> void:
	if _refresh_again and not _busy and visible:
		_refresh_again = false
		refresh()


func refresh() -> void:
	if _busy:
		_refresh_again = true
		return
	if not visible:
		return
	_busy = true
	_friends.visible = _view.selected == 1
	var path := "/social/wishlist"
	if _view.selected == 1:
		if target_id <= 0:
			_busy = false
			_rows.clear()
			_items.clear()
			_status.text = "Add a friend using the Social panel first."
			return
		path = "/social/players/%d/wishlist" % target_id
	elif _view.selected == 2:
		path = "/social/gifts"
	var selected_view := _view.selected
	var selected_target := target_id
	var selected_code := str(_selected().get("item_code", ""))
	var response: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_GET, path)
	_busy = false
	if not visible or selected_view != _view.selected or selected_target != target_id:
		_refresh_again = true
		return
	_rows.clear()
	_items.clear()
	if not _result(response):
		return
	var data: Variant = APIClient.data_of(response)
	_rows = data if data is Array else data.get("items", [])
	for row in _rows:
		var text := "%s × %d" % [_catalog.get(str(row["item_code"]), row["item_code"]), row["quantity"]]
		if _view.selected == 2:
			text += " · Claimed" if row.get("claimed", false) else " · Ready to claim"
		else:
			text += " · %d remaining · %d pending" % [row["remaining_quantity"], row["pending_quantity"]]
		_items.add_item(text)
		if str(row["item_code"]) == selected_code:
			_items.select(_items.item_count - 1)
	_status.text = "Select an item to create a wish or send a gift."


func _selected() -> Dictionary:
	var indices := _items.get_selected_items()
	return _rows[indices[0]] if not indices.is_empty() and indices[0] < _rows.size() else {}


func _select(_index: int) -> void:
	var row := _selected()
	select_code(str(row.get("item_code", "")))
	_quantity.value = int(row.get("quantity", 1)) if _view.selected == 0 else 1
	_priority.value = int(row.get("priority", 0))


func _save() -> void:
	if _busy or _view.selected != 0 or item_code().is_empty():
		return
	_busy = true
	var code := item_code()
	var old: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_GET, "/social/wishlist/" + code.uri_encode())
	if not old.get("ok", false) and int(old.get("status_code", 0)) != 404:
		_busy = false
		_result(old)
		return
	var version := int(APIClient.data_of(old).get("version", 0)) if old.get("ok", false) else 0
	var selected := _selected()
	if selected.get("item_code") == code:
		version = int(selected["version"])
	var response: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_PUT, "/social/wishlist/" + code.uri_encode(), {"quantity": int(_quantity.value), "priority": int(_priority.value), "expected_version": version})
	_busy = false
	if _result(response):
		await refresh()


func _remove() -> void:
	var row := _selected()
	if _busy or _view.selected != 0 or row.is_empty():
		return
	_busy = true
	var response: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_DELETE, "/social/wishlist/%s?expected_version=%d" % [str(row["item_code"]).uri_encode(), row["version"]])
	_busy = false
	if _result(response):
		await refresh()


func _pending_path() -> String:
	return "user://gift_pending_%s_%d.json" % [APIClient.base_url.sha256_text(), Global.player_id]


func _pending() -> Dictionary:
	if not FileAccess.file_exists(_pending_path()):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(_pending_path()))
	if not data is Dictionary:
		return {}
	# Godot JSON parsing returns numbers as floats; the API requires integers.
	for key in ["target_id", "quantity", "wishlist_entry_id", "wishlist_version"]:
		if data.has(key):
			data[key] = int(data[key])
	return data


func _store_pending(value: Dictionary) -> bool:
	var file := FileAccess.open(_pending_path(), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value))
	file.flush()
	return file.get_error() == OK


func _prepare_gift() -> void:
	if _busy or _view.selected != 1 or target_id <= 0 or item_code().is_empty():
		return
	if not _pending().is_empty():
		_status.text = "Recover the pending gift before sending another."
		return
	_proposal = {"target_id": target_id, "item_code": item_code(), "quantity": int(_quantity.value), "request_id": APIClient.realtime.new_request_id()}
	var row := _selected()
	if row.get("item_code") == _proposal["item_code"]:
		_proposal["wishlist_entry_id"] = int(row["id"])
		_proposal["wishlist_version"] = int(row["version"])
	_confirm.dialog_text = "Send %d × %s to %s? Items will leave your inventory." % [_proposal["quantity"], _catalog.get(str(_proposal["item_code"]), _proposal["item_code"]), _friends.get_item_text(_friends.selected)]
	_confirm.popup_centered()


func _send_gift() -> void:
	if _busy or _proposal.is_empty():
		return
	if not _store_pending(_proposal):
		_status.text = "Could not save gift request. Nothing was sent."
		return
	_proposal.clear()
	_recover()


func _recover() -> void:
	if _busy:
		return
	var pending := _pending()
	if pending.is_empty():
		_status.text = "No pending gift."
		return
	_busy = true
	var receipt: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_GET, "/social/gifts/requests/" + str(pending["request_id"]))
	if receipt.get("stale", false) or not receipt.get("ok", false):
		_busy = false
		_result(receipt)
		return
	var response := receipt
	if not APIClient.data_of(receipt).get("found", false):
		response = await APIClient.authenticated(HTTPClient.METHOD_POST, "/social/gifts", pending)
	_busy = false
	if response.get("stale", false):
		return
	var status := int(response.get("status_code", 0))
	if response.get("ok", false) or (status >= 400 and status < 500 and status not in [401, 408, 429]):
		_store_pending({})
	if _result(response):
		_status.text = "Gift delivered to their inbox."
		GameState.refresh_gameplay()
	else:
		_status.text += " Use Recover pending gift if delivery is uncertain."


func _claim() -> void:
	var row := _selected()
	if _busy or _view.selected != 2 or row.is_empty():
		return
	_busy = true
	var response: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_POST, "/social/gifts/%d/claim" % row["id"])
	_busy = false
	if _result(response):
		GameState.refresh_gameplay()
		await refresh()


func _save_preferences() -> void:
	if _busy:
		return
	_busy = true
	var response: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_PATCH, "/social/preferences", {"voice_privacy": ["off", "friends", "nearby"][_privacy.selected], "wishlist_visibility": ["private", "friends"][_visibility.selected], "proximity_prompts": _prompts.button_pressed})
	_busy = false
	_result(response)
