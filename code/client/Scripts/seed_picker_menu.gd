extends CanvasLayer

signal seed_selected(seed_name: String)

@onready var panel: PanelContainer = %Panel
@onready var grid: GridContainer = %Grid
@onready var title: Label = %TitleLabel
var _buying := false
var _opening := 0


func _ready() -> void:
	WoodPanel.apply_panel_title_style(title)
	%Cancel.pressed.connect(hide_menu)
	$Screen/Outside.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			hide_menu()
			get_viewport().set_input_as_handled()
	)
	visible = false


func show_menu() -> void:
	_opening += 1
	var opening := _opening
	GameState.menu_open = true
	visible = true
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	title.text = "Choose a Seed · Aura %d" % int(GameState.economy.get("aura_balance", 0))
	var owned: Dictionary = {}
	for row in GameState.inventory:
		var code := str(row.get("item_code", ""))
		if not code.ends_with("_seed") or int(row.get("quantity", 0)) <= 0:
			continue
		var item: Dictionary = row.get("item", {})
		var seed := code.trim_suffix("_seed")
		var btn := _button(code, "%s\n×%d" % [item.get("name", seed.capitalize()), int(row["quantity"])])
		btn.tooltip_text = str(item.get("description", ""))
		btn.disabled = item.get("season", "all") not in ["all", GameState.world_state.get("current_season")]
		if btn.disabled:
			btn.text += "\n" + str(item.get("season", "")).capitalize() + " only"
		btn.pressed.connect(_on_seed_pressed.bind(seed))
		owned[code] = btn
	if owned.is_empty():
		title.text = "No seeds owned · Buy available seeds below"
	if Global.is_logged_in():
		var response: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_GET, "/shop")
		if opening != _opening or response.get("stale", false):
			return
		if response.get("ok", false):
			var catalog: Dictionary = APIClient.data_of(response)
			for item in catalog.get("items", []):
				var code := str(item.get("item_code", ""))
				if not code.ends_with("_seed"):
					continue
				if owned.has(code) and item.get("locked", false):
					owned[code].disabled = true
					owned[code].text += "\nLevel %d required" % int(item.get("required_level", 1))
				if not item.get("in_stock", false) or item.get("locked", false) or item.get("season") not in ["all", GameState.world_state.get("current_season")]:
					continue
				var buy := _button(code, "Buy %s\n%d Aura" % [code.trim_suffix("_seed").capitalize(), int(item["buy_value"])])
				buy.disabled = int(item["buy_value"]) > int(GameState.economy.get("aura_balance", 0))
				buy.pressed.connect(_buy_seed.bind(code))
		else:
			title.text = APIClient.error_text(response)


func _button(code: String, label: String) -> Button:
	var button := WoodButton.new()
	button.text = label
	button.icon = WoodPanel.item_icon(code)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 40)
	button.custom_minimum_size = Vector2(220, 82)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(button)
	button.add_theme_font_size_override("font_size", 18)
	return button


func hide_menu() -> void:
	_opening += 1
	GameState.menu_open = false
	visible = false


func _on_seed_pressed(seed_name: String) -> void:
	if _buying:
		return
	hide_menu()
	seed_selected.emit(seed_name)


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		hide_menu()
		get_viewport().set_input_as_handled()


func _buy_seed(code: String) -> void:
	if _buying:
		return
	_buying = true
	var version := Global.session_version
	var response: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_POST, "/shop/buy", {"item_code": code, "quantity": 1, "request_id": Crypto.new().generate_random_bytes(16).hex_encode()})
	await GameState.refresh_gameplay()
	_buying = false
	if version != Global.session_version or not visible:
		return
	await show_menu()
	if not response.get("ok", false):
		title.text = "Check your seeds before retrying." if int(response.get("status_code", 0)) == 0 else APIClient.error_text(response)
