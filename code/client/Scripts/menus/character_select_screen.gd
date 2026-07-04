extends Control

@onready var _grid: GridContainer = %CharacterGrid
@onready var _confirm_button: Button = %ConfirmButton
@onready var _back_button: Button = %BackButton
@onready var _status_label: Label = %StatusLabel

var _button_group := ButtonGroup.new()
var _characters: Array[Dictionary] = []


func _ready() -> void:
	_confirm_button.pressed.connect(_on_confirm)
	_back_button.pressed.connect(_on_back)

	var portrait_farmer_female := preload("res://Assets/watering_plants_wat/female_farmer_character_pink_hair_with_ribbon_flor/animations/Running-79e518a9/south/frame_000.png")

	_characters = [
		{"id": "farmer_male", "name": "Male Farmer", "locked": true},
		{"id": "farmer_female", "name": "Female Farmer", "portrait": portrait_farmer_female},
		{"id": "explorer", "name": "Explorer", "locked": true},
		{"id": "mage", "name": "Mage", "locked": true},
	]

	var preload_card := preload("res://Scenes/components/UISpriteSelector.tscn")
	for c in _characters:
		var card = preload_card.instantiate()
		if c.get("locked", false):
			card.disabled = true
			card.modulate = Color(0.4, 0.4, 0.4, 0.6)
		else:
			card.button_group = _button_group
		_grid.add_child(card)
		card.set_character(c.id, c.name, c.get("portrait"))

	var applied := false
	for child in _grid.get_children():
		if child.has_method("get_character_id") and not child.disabled:
			if child.character_id == Global.selected_character:
				child.button_pressed = true
				applied = true
				break

	if not applied:
		for child in _grid.get_children():
			if child.has_method("get_character_id") and not child.disabled:
				child.button_pressed = true
				break


func _on_confirm() -> void:
	var pressed = _button_group.get_pressed_button()
	if pressed and pressed.has_method("get_character_id"):
		Global.selected_character = pressed.character_id
		Global.save_session()
		SceneManager.goto_map_selection()


func _on_back() -> void:
	SceneManager.goto_map_selection()
