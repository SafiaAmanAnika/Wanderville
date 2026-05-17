extends Control

@onready var _world_button: Button = $Center/VBox/WorldButton
@onready var _logout_button: Button = $Center/VBox/LogoutButton


func _ready() -> void:
	_world_button.pressed.connect(_on_world_pressed)
	_logout_button.pressed.connect(_on_logout_pressed)


func _on_world_pressed() -> void:
	# TODO: Load the actual game world scene
	print("Loading world... (not implemented yet)")


func _on_logout_pressed() -> void:
	Global.clear_session()
	SceneManager.goto_login()
