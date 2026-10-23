extends CanvasLayer
# Tabs on top, scrollable item grid, info line, Close.  picked("fridge") when you click an item.

signal picked(item_name: String)
signal closed

var _grid: GridContainer
var _info: Label


func _ready() -> void:
	layer = 30
	GameState.menu_open = true
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 480)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)

	var tabs := HFlowContainer.new()
	box.add_child(tabs)
	for tab in FurnitureCatalog.TABS:
		var b := Button.new()
		b.text = FurnitureCatalog.TAB_NAMES[tab]
		b.pressed.connect(_show_tab.bind(tab))
		tabs.add_child(b)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 320)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 8
	scroll.add_child(_grid)

	_info = Label.new()
	box.add_child(_info)

	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(_close)
	box.add_child(close)

	_show_tab("seating")
	await get_tree().process_frame
	panel.position = (panel.get_viewport_rect().size - panel.size) / 2.0   # centre it


func _show_tab(tab: String) -> void:
	for c in _grid.get_children():
		c.queue_free()
	var items := FurnitureCatalog.items_in_tab(tab)
	_info.text = "Nothing here yet." if items.is_empty() else "Pick something to place."
	for it in items:
		var b := Button.new()
		b.icon = FurnitureCatalog.icon(it)
		b.expand_icon = true
		b.custom_minimum_size = Vector2(80, 80)
		b.tooltip_text = it["name"]
		b.mouse_entered.connect(func() -> void:
			_info.text = "%s  —  %d wood" % [it["name"], int(it["wood_cost"])])
		b.pressed.connect(_pick.bind(String(it["id"])))
		_grid.add_child(b)


func _pick(item_name: String) -> void:
	picked.emit(item_name)
	_close()


func _close() -> void:
	GameState.menu_open = false
	closed.emit()
	queue_free()
