extends Control

const PIXEL_FONT := preload("res://Assets/fonts/BoldPixels.ttf")
const BG_TEXTURE := preload("res://Assets/background/bg.png")
const CharaFrames := preload("res://Scripts/chara_frames.gd")
const Avatar := preload("res://Scripts/customization/character_preview.gd")
const LobbyStyle := preload("res://Scripts/ui/lobby_theme.gd")

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
	_style_selection.call_deferred()

	WoodPanel.play_entrance(_form_panel)


func _populate_characters() -> void:
	var portrait_farmer_female := preload("res://Assets/watering_plants_wat/female_farmer_character_pink_hair_with_ribbon_flor/animations/Running-79e518a9/south/frame_000.png")

	_characters = []
	for id in Global.CHARACTERS:
		var info: Dictionary = Global.CHARACTERS[id]
		var folder: String = info["folder"]
		var portrait: Texture2D = portrait_farmer_female if folder == "" else null
		if folder != "": portrait = CharaFrames.portrait(folder)
		_characters.append({"id": id, "name": info["name"], "portrait": portrait})


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
		if c.id != "farmer_female": _add_preview(card, c.id)

	var create_card := _preload_card.instantiate()
	create_card.button_group = _button_group
	_grid.add_child(create_card)
	create_card.set_character("", "Create New", null)
	_add_preview(create_card, Global.selected_character)


func _add_preview(card: Button, code: String) -> void:
	var portrait := card.get_node("VBox/Portrait") as TextureRect
	portrait.texture = null
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.get_node("VBox").mouse_filter = Control.MOUSE_FILTER_IGNORE
	var avatar := Avatar.new()
	avatar.name = "CharacterPreview"
	avatar.character = code
	avatar.scale = Vector2.ONE * 0.65
	portrait.add_child(avatar)
	portrait.resized.connect(func(): avatar.position = portrait.size / 2.0 - Vector2(0, 6))
	avatar.position = portrait.size / 2.0


func _style_selection() -> void:
	LobbyStyle.apply_tree(self)
	var title := _form_panel.get_node("VBox/Title") as Label
	title.add_theme_stylebox_override("normal", LobbyStyle.box(LobbyStyle.MAROON, 12))
	title.add_theme_color_override("font_color", Color("fff0d9"))
	for card in _grid.get_children():
		card._style_normal = LobbyStyle.box(Color("efd6b4"), 12)
		card._style_hover = LobbyStyle.box(Color("ffe9c8"), 12)
		card._style_selected = LobbyStyle.box(Color("e1c49b"), 12)
		card._style_selected.border_color = LobbyStyle.MAROON
		card._update_visuals()
		card.modulate = Color.WHITE
		card.toggled.connect(func(_pressed: bool): card.modulate = Color.WHITE)


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
			# The customization room previews the current character in place;
			# no character is created or saved until its panels exist.
			SceneManager.goto_character_customization()
			return
		if Global.is_logged_in():   # offline: just remember it locally
			_confirm_button.disabled = true
			var response: Dictionary = await APIClient.update_profile({"character_code": cid})
			_confirm_button.disabled = false
			if not bool(response.get("ok", false)):
				_status_label.text = APIClient.error_text(response)
				return
		# Original character IDs and artwork; no generated appearance overlay.
		if cid != Global.selected_character:
			Global.modular_look = {}
			Global.appearance_changed.emit()
		Global.selected_character = cid
		Global.selected_world_id = ""
		Global.save_session()
		SceneManager.goto_map_showcase()


func _on_back() -> void:
	SceneManager.goto_map_selection()
