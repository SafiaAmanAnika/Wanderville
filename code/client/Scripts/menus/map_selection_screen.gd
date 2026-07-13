extends Control

const PIXEL_FONT := preload("res://Assets/fonts/BoldPixels.ttf")
const BG_TEXTURE := preload("res://Assets/background/bg.png")

const TEXT_COLOR := Color(0.95, 0.91, 0.80)
const TEXT_SECONDARY := Color(0.82, 0.74, 0.58)

@onready var _bg: TextureRect = %Background
@onready var _form_panel: PanelContainer = %FormPanel
@onready var _subtitle: Label = %Subtitle
@onready var _settings_overlay: Control = $SettingsOverlay
@onready var _logout_dialog: Control = $LogoutConfirmationDialog
@onready var _play_btn: WoodButton = %PlayButton
@onready var _manage_chars_btn: WoodButton = %ManageCharsButton
@onready var _manage_worlds_btn: WoodButton = %ManageWorldsButton
@onready var _settings_btn: WoodButton = %SettingsButton
@onready var _logout_btn: WoodButton = %LogoutButton


func _ready() -> void:
	_bg.texture = BG_TEXTURE

	var title_label: Label = %Title if %Title else _form_panel.get_node_or_null("VBox/Title")
	if title_label:
		WoodPanel.apply_panel_title_style(title_label)

	WoodPanel.apply_subtitle_style(_subtitle)

	if Global.display_name != "":
		_subtitle.text = "Welcome back, %s!" % Global.display_name

	_play_btn.pressed.connect(_on_play)
	_manage_chars_btn.pressed.connect(_on_manage_chars)
	_manage_worlds_btn.pressed.connect(_on_manage_worlds)
	_settings_btn.pressed.connect(_on_settings)
	_logout_btn.pressed.connect(_on_logout)

	if _settings_overlay:
		_settings_overlay.hide()

	if _logout_dialog:
		_logout_dialog.hide()

	WoodPanel.play_entrance(_form_panel)


func _on_play() -> void:
	if Global.selected_character != "" and Global.selected_world_id != "":
		SceneManager.goto_world()
	else:
		SceneManager.goto_character_select()


func _on_manage_chars() -> void:
	SceneManager.goto_character_select()


func _on_manage_worlds() -> void:
	SceneManager.goto_map_showcase()


func _on_settings() -> void:
	if _settings_overlay:
		_settings_overlay.show_overlay()
		_settings_overlay.move_to_front()


func _on_logout() -> void:
	if _logout_dialog:
		_logout_dialog.show_dialog()
