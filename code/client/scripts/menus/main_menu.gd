extends Control

@onready var _world_button: Button = $Center/VBox/WorldButton
@onready var _logout_button: Button = $Center/VBox/LogoutButton


func _ready() -> void:
	_world_button.pressed.connect(_on_world_pressed)
	_logout_button.pressed.connect(_on_logout_pressed)


func _on_world_pressed() -> void:
	if await GameState.load_from_backend():
		SceneManager.goto_post_login()


func _on_logout_pressed() -> void:
	await APIClient.logout()
	SceneManager.goto_login()
