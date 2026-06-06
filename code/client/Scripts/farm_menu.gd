extends CanvasLayer

@onready var level1: HBoxContainer = $ColorRect/Level1Container
@onready var level2: HBoxContainer = $ColorRect/Level2Container
@onready var hint_label: Label = $ColorRect/HintLabel

var level1_options: Array[PanelContainer] = []
var level2_options: Array[PanelContainer] = []

var current_level: int = 1
var selected_index: int = 0

var normal_color: Color = Color(0.17, 0.17, 0.17, 1.0)
var selected_color: Color = Color(0.4, 0.6, 0.3, 1.0)

func _ready():
	visible = false
	for child in level1.get_children():
		if child is PanelContainer:
			level1_options.append(child)
	for child in level2.get_children():
		if child is PanelContainer:
			level2_options.append(child)

func open():
	visible = true
	GameState.menu_open = true
	current_level = 1
	selected_index = 0
	level1.visible = true
	level2.visible = false
	hint_label.text = "← → to choose  |  Enter to select  |  Esc to close"
	_update_highlight()

func close():
	visible = false
	GameState.menu_open = false
	selected_index = 0

func _process(_delta):
	if not visible:
		return

	if Input.is_action_just_pressed("ui_left"):
		selected_index -= 1
		_clamp_index()
		_update_highlight()
	elif Input.is_action_just_pressed("ui_right"):
		selected_index += 1
		_clamp_index()
		_update_highlight()

	if Input.is_action_just_pressed("ui_accept"):
		_on_confirm()

	if Input.is_action_just_pressed("ui_cancel"):
		if current_level == 2:
			current_level = 1
			selected_index = 0
			level1.visible = true
			level2.visible = false
			hint_label.text = "← → to choose  |  Enter to select  |  Esc to close"
			_update_highlight()
		else:
			close()

func _clamp_index():
	var options = level1_options if current_level == 1 else level2_options
	if selected_index < 0:
		selected_index = options.size() - 1
	elif selected_index >= options.size():
		selected_index = 0

func _update_highlight():
	var options = level1_options if current_level == 1 else level2_options
	for i in range(options.size()):
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = selected_color if i == selected_index else normal_color
		options[i].add_theme_stylebox_override("panel", style)

func _on_confirm():
	if current_level == 1:
		if selected_index == 0:  # Farm
			current_level = 2
			selected_index = 0
			level1.visible = false
			level2.visible = true
			hint_label.text = "← → to choose  |  Enter to select  |  Esc to go back"
			_update_highlight()
		else:  # Water Plants
			close()
			GameState.set_mode("water")
	else:  # Level 2
		if selected_index == 0:  # Sow Seeds
			close()
			GameState.set_mode("sow")
		else:  # Place Farm Tile
			close()
			GameState.set_mode("place_tile")
