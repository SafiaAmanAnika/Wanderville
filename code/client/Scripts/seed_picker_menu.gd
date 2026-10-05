extends CanvasLayer

signal seed_selected(seed_name: String)

@onready var panel: PanelContainer = %Panel
@onready var grid: GridContainer = %Grid
@onready var title: Label = %TitleLabel
var _snapshot := ""
var _selected_code := ""


func _ready() -> void:
	WoodPanel.apply_panel_title_style(title)
	WoodPanel.apply_status_label(%Hint)
	%Cancel.pressed.connect(hide_menu)
	%Store.pressed.connect(func() -> void:
		hide_menu()
		GameState.store_requested.emit()
	)
	$Screen/Outside.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			hide_menu()
			get_viewport().set_input_as_handled()
	)
	GameState.inventory_updated.connect(func(_items: Array) -> void: _render())
	GameState.world_updated.connect(func(_data: Dictionary) -> void: _render())
	GameState.experience_updated.connect(func(_data: Dictionary) -> void: _render())
	Global.session_changed.connect(func() -> void:
		_selected_code = ""
		_snapshot = ""
		hide_menu()
	)
	visible = false


func show_menu() -> void:
	GameState.menu_open = true
	visible = true
	_snapshot = ""
	_render()
	%Cancel.grab_focus()


func _render() -> void:
	if not visible or not is_node_ready():
		return
	var season := str(GameState.world_state.get("current_season", ""))
	var level := int(GameState.experience.get("level", 1))
	var snapshot := JSON.stringify(GameState.inventory) + season + str(level)
	if snapshot == _snapshot:
		return
	_snapshot = snapshot
	var scroll: int = %Scroll.scroll_vertical
	var focused := get_viewport().gui_get_focus_owner()
	var focused_code := str(focused.get_meta("item_code", "")) if focused else ""
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	title.text = "Choose a seed · " + season.capitalize()
	%Hint.text = "Choose once to plant. Cancel keeps your seeds."
	# Several inventory stacks represent one plantable seed choice.
	var owned: Dictionary = {}
	for row in GameState.inventory:
		var item: Dictionary = row.get("item", {})
		if item.get("category") != "seed" or int(row.get("quantity", 0)) <= 0:
			continue
		var code := str(row.get("item_code", ""))
		if not owned.has(code):
			owned[code] = row.duplicate(true)
			owned[code]["quantity"] = 0
		owned[code]["quantity"] += int(row["quantity"])
	for code in owned:
		var row: Dictionary = owned[code]
		var item: Dictionary = row.get("item", {})
		var crop := str(row.get("harvest_code", "")) if row.get("harvest_code") != null else ""
		var reasons: Array[String] = []
		if crop == "":
			reasons.append("Planting unavailable")
		if int(row.get("required_level", 1)) > level:
			reasons.append("Requires Level %d" % int(row["required_level"]))
		if item.get("season", "all") not in ["all", season]:
			reasons.append(str(item["season"]).capitalize() + " crop")
		var button := WoodButton.new()
		button.text = "%s\n×%d" % [item.get("name", code), int(row["quantity"])]
		if not reasons.is_empty():
			button.text += "\n" + "\n".join(reasons)
		button.disabled = not reasons.is_empty()
		button.toggle_mode = true
		button.set_pressed_no_signal(code == _selected_code)
		button.tooltip_text = "%s\nProduces: %s\nPlanting season: %s" % [str(item.get("description", "")), crop.replace("_", " ").capitalize(), str(item.get("season", "all")).capitalize()]
		button.icon = WoodPanel.item_icon(code)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 40)
		button.custom_minimum_size = Vector2(220, 82)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.set_meta("item_code", code)
		button.pressed.connect(_on_seed_pressed.bind(crop, str(code)))
		grid.add_child(button)
		button.add_theme_font_size_override("font_size", 18)
		button.add_theme_stylebox_override("pressed", WoodPanel.make_wood_card_selected_style())
		button.add_theme_stylebox_override("focus", WoodPanel.make_wood_card_selected_style())
		if code == focused_code and not button.disabled:
			button.grab_focus()
	%Scroll.set_deferred("scroll_vertical", scroll)
	if grid.get_child_count() == 0:
		title.text = "No seeds owned · Visit the store"
		%Hint.text = "Claim starter seeds or buy more at the store."


func hide_menu() -> void:
	GameState.menu_open = false
	visible = false


func _on_seed_pressed(seed_name: String, item_code: String = "") -> void:
	# Closing before the signal also blocks a repeated input on the same tile.
	if not visible:
		return
	_selected_code = item_code
	hide_menu()
	seed_selected.emit(seed_name)


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		hide_menu()
		get_viewport().set_input_as_handled()
