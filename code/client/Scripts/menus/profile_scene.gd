extends Control

const BG_TEXTURE := preload("res://Assets/background/bg.webp")
const CharaFrames := preload("res://Scripts/chara_frames.gd")
const _preload_card := preload("res://Scenes/components/UISpriteSelector.tscn")

@onready var _bg: TextureRect = %Background
@onready var _title: Label = %Title
@onready var _username_label: Label = %UsernameLabel
@onready var _email_label: Label = %EmailLabel
@onready var _joined_label: Label = %JoinedLabel
@onready var _name_input: LineEdit = %NameInput
@onready var _save_name_button: Button = %SaveNameButton
@onready var _coins_label: Label = %CoinsLabel
@onready var _level_label: Label = %LevelLabel
@onready var _water_label: Label = %WaterLabel
@onready var _char_grid: GridContainer = %CharGrid
@onready var _status_label: Label = %StatusLabel
@onready var _back_button: Button = %BackButton

var _button_group := ButtonGroup.new()


func _ready() -> void:
	_bg.texture = BG_TEXTURE
	WoodPanel.apply_panel_title_style(_title)
	preload("res://Scripts/ui/loading_progress.gd").attach(_status_label)
	_save_name_button.pressed.connect(_on_save_name)
	_back_button.pressed.connect(_on_back)
	_button_group.pressed.connect(_on_character_pressed)
	_build_character_grid()
	_preselect_character()
	_refresh_stats()
	WoodPanel.play_entrance(%Panel)
	_load_game_data()


func _load_game_data() -> void:
	if not Global.is_logged_in() or GameState.backend_ready:
		return
	_status_label.text = "Loading profile..."
	var ok := await GameState.load_from_backend()
	_refresh_stats()
	_preselect_character()
	_status_label.text = "" if ok else GameState.last_error


func _build_character_grid() -> void:
	var portrait_farmer_female := preload("res://Assets/watering_plants_wat/female_farmer_character_pink_hair_with_ribbon_flor/animations/Running-79e518a9/south/frame_000.png")
	for id in Global.CHARACTERS:
		var info: Dictionary = Global.CHARACTERS[id]
		var folder: String = info["folder"]
		var portrait: Texture2D = portrait_farmer_female if folder == "" else CharaFrames.portrait(folder)
		var card := _preload_card.instantiate()
		card.button_group = _button_group
		_char_grid.add_child(card)
		card.set_character(id, info["name"], portrait)


func _preselect_character() -> void:
	var applied := false
	for child in _char_grid.get_children():
		if child.has_method("get_character_id") and not child.disabled:
			child.button_pressed = false
			if child.character_id == Global.selected_character:
				child.button_pressed = true
				applied = true
	if applied:
		return
	for child in _char_grid.get_children():
		if child.has_method("get_character_id") and not child.disabled:
			child.button_pressed = true
			break


func _refresh_stats() -> void:
	var profile: Dictionary = GameState.profile
	_username_label.text = Global.username
	_name_input.text = Global.display_name
	_email_label.text = Global.email
	_joined_label.text = "Member since %s" % str(profile.get("joined_at", ""))
	var econ: Dictionary = GameState.economy
	var coins := int(econ.get("taka_balance", econ.get("aura_balance", 0)))
	_coins_label.text = "Coins: %d" % coins
	var xp: Dictionary = GameState.experience
	_level_label.text = "Level %s (%s XP)" % [xp.get("level", 1), xp.get("total_xp", 0)]
	_water_label.text = "Water: %d / %d" % [GameState.water_drops, GameState.MAX_WATER]


func _on_character_pressed(button: Button) -> void:
	if not button.has_method("get_character_id"):
		return
	var cid: String = button.character_id
	if cid == Global.selected_character:
		return
	if Global.is_logged_in():
		_status_label.text = "Saving character..."
		var response: Dictionary = await APIClient.update_profile({"character_code": cid})
		if not bool(response.get("ok", false)):
			_preselect_character()
			_status_label.text = APIClient.error_text(response)
			return
	Global.selected_character = cid
	# These cards select original character scenes. Clear a previously saved
	# complete-look overlay so it cannot disguise the newly selected character.
	Global.modular_look = {}
	Global.appearance_changed.emit()
	Global.save_session()
	_status_label.text = "Character updated!"


func _on_save_name() -> void:
	var new_name := _name_input.text.strip_edges()
	if new_name.is_empty():
		_status_label.text = "Enter a display name first."
		return
	if new_name == Global.display_name:
		_status_label.text = "Nothing to change."
		return
	if Global.is_logged_in():
		_save_name_button.disabled = true
		_status_label.text = "Saving..."
		var response: Dictionary = await APIClient.update_profile({"display_name": new_name})
		_save_name_button.disabled = false
		if not bool(response.get("ok", false)):
			_status_label.text = APIClient.error_text(response)
			return
		Global.display_name = new_name
		Global.save_session()
	_status_label.text = "Display name updated!"


func _on_back() -> void:
	SceneManager.goto_post_login()
