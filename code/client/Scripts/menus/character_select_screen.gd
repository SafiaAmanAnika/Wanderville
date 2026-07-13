extends Control

const PIXEL_FONT := preload("res://Assets/fonts/BoldPixels.ttf")
const BG_TEXTURE := preload("res://Assets/background/bg.png")

@onready var _bg: TextureRect = %Background
@onready var _grid: GridContainer = %CharacterGrid
@onready var _confirm_button: Button = %ConfirmButton
@onready var _back_button: Button = %BackButton
@onready var _status_label: Label = %StatusLabel
@onready var _form_panel: PanelContainer = %FormPanel

var _button_group := ButtonGroup.new()
var _characters: Array[Dictionary] = []
var _preload_card := preload("res://Scenes/components/UISpriteSelector.tscn")


func _ready() -> void:
	_bg.texture = BG_TEXTURE

	_confirm_button.pressed.connect(_on_confirm)
	_back_button.pressed.connect(_on_back)

	var title_label: Label = _form_panel.get_node("VBox/Title")
	WoodPanel.apply_panel_title_style(title_label)

	_populate_characters()
	_build_grid()
	_select_previous_character()

	WoodPanel.play_entrance(_form_panel)


func _populate_characters() -> void:
	var portrait_farmer_female := preload("res://Assets/watering_plants_wat/female_farmer_character_pink_hair_with_ribbon_flor/animations/Running-79e518a9/south/frame_000.png")

	_characters = [
		{"id": "farmer_male", "name": "Male Farmer", "locked": true},
		{"id": "farmer_female", "name": "Female Farmer", "portrait": portrait_farmer_female},
		{"id": "explorer", "name": "Explorer", "locked": true},
		{"id": "mage", "name": "Mage", "locked": true},
	]


func _build_grid() -> void:
	for c in _characters:
		var card := _preload_card.instantiate()
		if c.get("locked", false):
			card.disabled = true
			card.modulate = Color(0.4, 0.4, 0.4, 0.6)
		else:
			card.button_group = _button_group
		_grid.add_child(card)
		card.set_character(c.id, c.name, c.get("portrait"))

	var create_card := _preload_card.instantiate()
	create_card.button_group = _button_group
	_grid.add_child(create_card)
	create_card.set_character("", "Create New", null)
	create_card.modulate = Color(0.65, 0.75, 0.55, 1.0)


func _select_previous_character() -> void:
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
	var pressed := _button_group.get_pressed_button()
	if pressed and pressed.has_method("get_character_id"):
		var cid: String = pressed.character_id
		if cid == "":
			_status_label.text = "Create New coming soon!"
			return
		Global.selected_character = cid
		Global.selected_world_id = ""
		Global.save_session()
		SceneManager.goto_map_selection()


func _on_back() -> void:
	SceneManager.goto_map_selection()
