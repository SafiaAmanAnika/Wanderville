extends Control

@onready var _settings_overlay: Control = $SettingsOverlay
@onready var _logout_dialog: ConfirmationDialog = $LogoutConfirmationDialog
@onready var _subtitle: Label = %Subtitle


func _ready() -> void:
	%CharacterSelectButton.pressed.connect(_on_character_select)
	%SelectMapButton.pressed.connect(_on_select_map)
	%SettingsButton.pressed.connect(_on_settings)
	%LogoutButton.pressed.connect(_on_logout)

	if _settings_overlay:
		_settings_overlay.hide()

	if Global.display_name != "":
		_subtitle.text = "Welcome back, %s!" % Global.display_name


func _on_character_select() -> void:
	SceneManager.goto_character_select()


func _on_select_map() -> void:
	SceneManager.goto_map_showcase()


func _on_settings() -> void:
	if _settings_overlay:
		_settings_overlay.show()
		_settings_overlay.move_to_front()


func _on_logout() -> void:
	_logout_dialog.popup_centered()
