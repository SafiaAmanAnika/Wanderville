extends CanvasLayer
const CROP_ART = preload("res://Scripts/crop_catalog.gd")

@onready var level1: HBoxContainer = $ColorRect/Level1Container
@onready var level2: HBoxContainer = $ColorRect/Level2Container
@onready var hint_label: Label = $ColorRect/HintLabel

var level1_options: Array[PanelContainer] = []
var level2_options: Array[PanelContainer] = []

var current_level: int = 1
var selected_index: int = 0

var normal_color: Color = Color(0.17, 0.17, 0.17, 1.0)
var selected_color: Color = Color(0.4, 0.6, 0.3, 1.0)

var seed_list: Array[String] = []   # filled from CROPS in _ready
var seed_index: int = 0

func _ready():
	visible = false
	# Only crops that actually have art can be offered.
	for crop in CROP_ART.ids():
		seed_list.append(str(crop))
	for child in level1.get_children():
		if child is PanelContainer:
			level1_options.append(child)
	for child in level2.get_children():
		if child is PanelContainer:
			level2_options.append(child)
	GameState.seed_changed.connect(_on_seed_changed)

func open():
	visible = true
	GameState.menu_open = true
	current_level = 1
	selected_index = 0
	seed_index = 0
	level1.visible = true
	level2.visible = false
	hint_label.text = "← → to choose  |  Enter to select  |  Esc to close"
	_update_highlight()

func close():
	visible = false
	GameState.menu_open = false
	selected_index = 0

func _process(_delta):
	if GameState.social_open:
		return
	if not visible:
		# Seed cycling when in sow mode outside menu
		if GameState.farm_mode == "sow":
			if Input.is_action_just_pressed("ui_up"):
				_cycle_seed(-1)
			elif Input.is_action_just_pressed("ui_down"):
				_cycle_seed(1)
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
			_go_back_to_level1()
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
		match selected_index:
			0:  # Farm → Level 2
				current_level = 2
				selected_index = 0
				level1.visible = false
				level2.visible = true
				hint_label.text = "← → to choose  |  Enter to select  |  Esc to go back"
				_update_highlight()
			1:  # Water Plants
				close()
				GameState.set_mode("water")
	else:  # Level 2
		match selected_index:
			0:  # Sow Seeds
				_pick_available_seed()
				if GameState.selected_seed != "":
					close()
					GameState.set_mode("sow")
					_update_sow_hint()
				else:
					hint_label.text = "No seeds available!"
			1:  # Place Farm Tile / Till
				close()
				GameState.set_mode("till")

func _go_back_to_level1():
	current_level = 1
	selected_index = 0
	level1.visible = true
	level2.visible = false
	hint_label.text = "← → to choose  |  Enter to select  |  Esc to close"
	_update_highlight()

func _pick_available_seed():
	for i in range(seed_list.size()):
		var seed = seed_list[i]
		if GameState.seed_inventory.get(seed, 0) > 0:
			seed_index = i
			GameState.set_seed(seed)
			return
	GameState.set_seed("")

func _cycle_seed(direction: int):
	var start = seed_index
	while true:
		seed_index = (seed_index + direction + seed_list.size()) % seed_list.size()
		var seed = seed_list[seed_index]
		if GameState.seed_inventory.get(seed, 0) > 0:
			GameState.set_seed(seed)
			_update_sow_hint()
			return
		if seed_index == start:
			break

func _update_sow_hint():
	var seed = GameState.selected_seed
	var count = GameState.seed_inventory.get(seed, 0)
	hint_label.text = "Seed: %s (%d)  |  ↑↓ to change  |  Click to plant" % [seed, count]

func _on_seed_changed(_seed: String = ""):
	if GameState.farm_mode == "sow" and not visible:
		_update_sow_hint()
