extends VBoxContainer

var _catalog: Array = []
var _rows: Array = []
var _selected_code := ""
var _claimed := false
var _busy := false
var _loaded := false
var _snapshot := ""
var _starter_items: Dictionary = {}
var _level := -1
var _world_fraction := -1.0
var _catalog_stale := false
var _pending_resolved := false
var _resolved_message := ""


func _ready() -> void:
	for label in [%Balance, %Details, %QuantityLabel, %Status]:
		WoodPanel.apply_status_label(label)
	%QuantityLabel.autowrap_mode = TextServer.AUTOWRAP_OFF
	for control in [%Items, %Mode]:
		control.add_theme_font_override("font", WoodPanel.PIXEL_FONT)
		control.add_theme_font_size_override("font_size", 18)
	%Items.add_theme_stylebox_override("panel", WoodPanel.make_wood_card_style())
	for style in ["selected", "selected_focus"]:
		%Items.add_theme_stylebox_override(style, WoodPanel.make_wood_card_selected_style())
	%Items.add_theme_color_override("font_color", WoodPanel.TEXT_COLOR)
	%Items.add_theme_color_override("font_selected_color", WoodPanel.TEXT_COLOR)
	%Quantity.get_line_edit().add_theme_font_override("font", WoodPanel.PIXEL_FONT)
	%Mode.item_selected.connect(func(_index: int) -> void:
		_selected_code = ""
		%Quantity.set_value_no_signal(1)
		_render()
	)
	%Items.item_selected.connect(func(index: int) -> void:
		_selected_code = str(_rows[index]["item_code"])
		_details()
	)
	%Quantity.value_changed.connect(func(_value: float) -> void: _details())
	%Trade.pressed.connect(_trade)
	%Starter.pressed.connect(_claim)
	%Refresh.pressed.connect(open_store)
	%Retry.pressed.connect(func() -> void: _submit_pending())
	GameState.inventory_updated.connect(func(_items: Array) -> void:
		var snapshot := JSON.stringify(GameState.inventory_summary)
		if snapshot != _snapshot:
			_snapshot = snapshot
			_render()
	)
	GameState.economy_updated.connect(func(_data: Dictionary) -> void: _details())
	GameState.experience_updated.connect(func(data: Dictionary) -> void:
		var level := int(data.get("level", 1))
		if level != _level:
			_level = level
			_render()
		else:
			_details()
	)
	GameState.world_updated.connect(_world_changed)
	Global.session_changed.connect(_clear_account)
	_details()


func _world_changed(data: Dictionary) -> void:
	var fraction := float(data.get("current_time_of_day", 0.0))
	if _world_fraction >= 0.0 and fraction < _world_fraction:
		_catalog_stale = true
	_world_fraction = fraction
	# The shared world refresh already observes day boundaries. Fetch only the
	# catalog when stock rotates; inventory still uses the shared refresh.
	if _catalog_stale and _loaded and is_visible_in_tree() and not _busy and APIClient.pending_shop().is_empty():
		open_store()
	else:
		_details()


func open_store() -> void:
	if _busy:
		return
	_busy = true
	_details()
	%Status.text = "Loading store..."
	var version := Global.session_version
	var response: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_GET, "/shop")
	if version != Global.session_version:
		return
	if response.get("ok", false):
		var data: Dictionary = APIClient.data_of(response)
		_catalog = data.get("items", [])
		_claimed = bool(data.get("starter", {}).get("claimed", false))
		_starter_items = data.get("starter", {}).get("items", {})
		_loaded = true
		_catalog_stale = false
		_catalog.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var a_seed := str(a.get("category", "")) == "seed"
			var b_seed := str(b.get("category", "")) == "seed"
			return a_seed if a_seed != b_seed else str(a["name"]) < str(b["name"])
		)
		%Status.text = "Seeds keep their planting seasons. Rare stock rotates each game day."
	else:
		_loaded = false
		%Status.text = APIClient.error_text(response)
	_busy = false
	_render()
	if not APIClient.pending_shop().is_empty():
		if _pending_resolved:
			_pending_resolved = not APIClient.save_pending_shop({})
			_details()
			%Status.text = _resolved_message + (" Local transaction record cleared." if not _pending_resolved else _local_record_error())
		else:
			await _reconcile()


func _render() -> void:
	if not is_node_ready():
		return
	var scroll: float = %Items.get_v_scroll_bar().value
	_rows.clear()
	%Items.clear()
	if %Mode.selected == 0:
		_rows = _catalog.duplicate()
	else:
		var owned: Dictionary = {}
		for stack in GameState.inventory:
			var item: Dictionary = stack.get("item", {}).duplicate()
			if int(item.get("sell_value", 0)) > 0:
				var code := str(stack["item_code"])
				if not owned.has(code):
					item["owned"] = 0
					owned[code] = item
				owned[code]["owned"] += int(stack["quantity"])
		_rows = owned.values()
		_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["name"]) < str(b["name"]))
	for row in _rows:
		var buying: bool = %Mode.selected == 0
		var price := int(row.get("buy_value", 0) if buying else row.get("sell_value", 0))
		var suffix := " · in stock" if buying and row.get("in_stock", false) else ""
		if not buying:
			suffix = " · owned %d" % int(row.get("owned", 0))
		if buying and not row.get("in_stock", false):
			suffix += " · out of stock"
		if buying and int(row.get("required_level", 1)) > int(GameState.experience.get("level", 1)):
			suffix += " · level %d" % int(row["required_level"])
		var index: int = %Items.add_item("%s · %d Aura%s" % [row["name"], price, suffix], WoodPanel.item_icon(row["item_code"]))
		%Items.set_item_tooltip(index, str(row.get("description", "")))
		if row["item_code"] == _selected_code:
			%Items.select(index)
	%Items.get_v_scroll_bar().set_deferred("value", scroll)
	_details()


func _selected() -> Dictionary:
	for row in _rows:
		if row["item_code"] == _selected_code:
			return row
	return {}


func _details() -> void:
	if not is_node_ready():
		return
	var aura := int(GameState.economy.get("aura_balance", 0))
	var capacity := int(GameState.inventory_summary.get("capacity", 0))
	var used := int(GameState.inventory_summary.get("used_slots", 0))
	%Balance.text = "Aura %d · Inventory %d / %d slots" % [aura, used, capacity]
	%Starter.visible = not _claimed
	%Starter.disabled = _busy or not _loaded
	%Starter.tooltip_text = _starter_description() + "\nClaimed once per account; earned items and Aura are preserved."
	%Refresh.disabled = _busy
	%Mode.disabled = _busy
	%Quantity.editable = not _busy
	var pending := APIClient.pending_shop()
	%Retry.visible = not pending.is_empty()
	%Retry.disabled = _busy or _pending_resolved
	%Trade.disabled = true
	var item := _selected()
	if item.is_empty():
		%Trade.text = "Buy" if %Mode.selected == 0 else "Sell"
		%Details.text = "No sellable items owned." if %Mode.selected == 1 and _rows.is_empty() else "Select an item."
		return
	var buying: bool = %Mode.selected == 0
	%Quantity.max_value = 99 if buying else maxi(1, int(item.get("owned", 0)))
	var quantity := int(%Quantity.value)
	var price := int(item.get("buy_value", 0) if buying else item.get("sell_value", 0))
	%Trade.text = "%s · %d Aura" % ["Buy" if buying else "Sell", price * quantity]
	var reasons: Array[String] = []
	if buying:
		if not item.get("in_stock", false):
			reasons.append("Out of stock today.")
		if int(item.get("required_level", 1)) > int(GameState.experience.get("level", 1)):
			reasons.append("Requires Level %d." % int(item["required_level"]))
		if price * quantity > aura:
			reasons.append("Not enough Aura.")
		if not GameState.inventory_summary.has("capacity"):
			reasons.append("Waiting for inventory capacity.")
		elif _new_slots_needed(item, quantity) > maxi(0, capacity - used):
			reasons.append("Inventory full: this purchase needs %d new slot(s)." % _new_slots_needed(item, quantity))
	elif quantity > int(item.get("owned", 0)):
		reasons.append("You do not own that many.")
	var description := str(item.get("description", "")) if item.get("description") != null else ""
	%Details.text = "%s · %d × %d Aura = %d Aura\n%s" % [item.get("name", ""), quantity, price, quantity * price, description]
	if buying:
		%Details.text += "\nRequired Level %d" % int(item.get("required_level", 1))
	if item.get("category") == "seed":
		%Details.text += "\nPlanting season: %s" % str(item.get("season", "all")).capitalize()
		if buying:
			if item.get("season", "all") not in ["all", GameState.world_state.get("current_season", "")]:
				%Details.text += "\nPlant in %s; buying does not change the season." % str(item.get("season", "")).capitalize()
	if not reasons.is_empty():
		%Details.text += "\n" + "\n".join(reasons)
	%Trade.disabled = _busy or not _loaded or not pending.is_empty() or not reasons.is_empty()


func _new_slots_needed(item: Dictionary, quantity: int) -> int:
	var stack_limit := maxi(1, int(item.get("max_stack", 99)))
	var remaining := quantity
	for stack in GameState.inventory:
		if stack.get("item_code") == item.get("item_code"):
			remaining -= maxi(0, stack_limit - int(stack.get("quantity", 0)))
	return ceili(float(maxi(0, remaining)) / stack_limit)


func _starter_description() -> String:
	var names: Array[String] = []
	for code in _starter_items:
		var item_name := str(code).replace("_", " ").capitalize()
		for item in _catalog:
			if item.get("item_code") == code:
				item_name = str(item["name"])
				break
		names.append("%s ×%d" % [item_name, int(_starter_items[code])])
	return ", ".join(names)


func _trade() -> void:
	if _busy or %Trade.disabled or _selected().is_empty():
		return
	var pending := {"action": "buy" if %Mode.selected == 0 else "sell", "item_code": _selected_code, "quantity": int(%Quantity.value), "request_id": Crypto.new().generate_random_bytes(16).hex_encode()}
	if not APIClient.save_pending_shop(pending):
		%Status.text = "Cannot save transaction locally. Purchase was not sent."
		return
	_pending_resolved = false
	await _submit_pending()


func _submit_pending() -> void:
	if _busy or _pending_resolved:
		return
	var pending := APIClient.pending_shop()
	if pending.is_empty():
		return
	_busy = true
	_details()
	%Status.text = "Submitting transaction..."
	var version := Global.session_version
	var body := {"item_code": pending["item_code"], "quantity": pending["quantity"], "request_id": pending["request_id"]}
	var response: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_POST, "/shop/" + str(pending["action"]), body)
	if version != Global.session_version:
		return
	if response.get("ok", false):
		_pending_resolved = not APIClient.save_pending_shop({})
		_resolved_message = "Confirmed: %s ×%d." % [pending["item_code"], pending["quantity"]]
		await GameState.refresh_gameplay()
		if version != Global.session_version:
			return
		_busy = false
		if _pending_resolved:
			_render()
		else:
			await open_store()
		if version != Global.session_version:
			return
		%Status.text = _resolved_message + (_local_record_error() if _pending_resolved else "")
		if not _loaded:
			%Status.text += " Store refresh failed; use Refresh to continue."
	elif int(response.get("status_code", 0)) >= 400 and int(response.get("status_code", 0)) < 500 and int(response.get("status_code", 0)) not in [408, 409]:
		_pending_resolved = not APIClient.save_pending_shop({})
		_resolved_message = APIClient.error_text(response)
		await GameState.refresh_gameplay()
		if version != Global.session_version:
			return
		_busy = false
		if _pending_resolved:
			_render()
		else:
			await open_store()
		if version != Global.session_version:
			return
		%Status.text = _resolved_message + (_local_record_error() if _pending_resolved else "")
	else:
		_busy = false
		await _reconcile()


func _reconcile() -> void:
	var pending := APIClient.pending_shop()
	if _busy or pending.is_empty():
		return
	_busy = true
	_details()
	var version := Global.session_version
	var response: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_GET, "/shop/transactions/%s?action=%s" % [pending["request_id"], pending["action"]])
	if version != Global.session_version:
		return
	var confirmed := false
	if response.get("ok", false):
		confirmed = bool(APIClient.data_of(response).get("found", false))
		if confirmed:
			_pending_resolved = not APIClient.save_pending_shop({})
			_resolved_message = "Transaction confirmed by the server."
	await GameState.refresh_gameplay()
	if version != Global.session_version:
		return
	_busy = false
	if confirmed and not _pending_resolved:
		await open_store()
		if version != Global.session_version:
			return
	else:
		_render()
	%Status.text = _resolved_message + (_local_record_error() if _pending_resolved else "") if confirmed else "Outcome not confirmed. Refresh to check, or retry the same saved transaction; its ID prevents a second charge."


func _local_record_error() -> String:
	return " Cannot clear the saved transaction locally. Use Refresh to try again; this transaction will not be resent."


func _claim() -> void:
	if _busy or _claimed or not _loaded:
		return
	_busy = true
	_details()
	var version := Global.session_version
	var response: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_POST, "/shop/starter/claim", {})
	if version != Global.session_version:
		return
	await GameState.refresh_gameplay()
	if version != Global.session_version:
		return
	_busy = false
	await open_store()
	if version != Global.session_version:
		return
	%Status.text = "Starter pack claimed: %s. It cannot be claimed twice." % _starter_description() if _claimed else (APIClient.error_text(response) if not response.get("ok", false) else "Refresh to check starter pack status.")


func _clear_account() -> void:
	_catalog.clear()
	_rows.clear()
	_starter_items.clear()
	_snapshot = ""
	_level = -1
	_world_fraction = -1.0
	_catalog_stale = false
	_pending_resolved = false
	_resolved_message = ""
	_selected_code = ""
	_claimed = false
	_loaded = false
	_busy = false
	%Items.clear()
	%Status.text = ""
	%Details.text = ""
	%Balance.text = ""
