extends Control

@onready var _title_ui: VBoxContainer = %VBox
@onready var _welcome_label: Label = $WelcomeLabel
@onready var _signup_button: Button = %SignUpButton
@onready var _login_button: Button = %LoginButton
@onready var _exit_button: Button = %ExitButton


func _ready() -> void:
	_signup_button.pressed.connect(_on_signup)
	_login_button.pressed.connect(_on_login)
	_exit_button.pressed.connect(_on_exit)
	_title_ui.hide()
	_welcome_label.hide()

	if Global.load_session():
		_welcome_label.text = "Welcome back, %s!" % Global.display_name
		_welcome_label.show()
		await get_tree().create_timer(2.0).timeout
		SceneManager.goto_map_selection()
		return

	_title_ui.show()


func _on_signup() -> void:
	SceneManager.goto_signup()


func _on_login() -> void:
	SceneManager.goto_login()


func _on_exit() -> void:
	get_tree().quit()
