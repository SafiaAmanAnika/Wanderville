extends Control

const PIXEL_FONT := preload("res://Assets/fonts/BoldPixels.ttf")
const BG_TEXTURE := preload("res://Assets/background/bg.png")

const TEXT_COLOR := Color(0.95, 0.91, 0.80)
const TEXT_SECONDARY := Color(0.82, 0.74, 0.58)

@onready var _bg: TextureRect = %Background
@onready var _content: VBoxContainer = %Content
@onready var _welcome_label: Label = %WelcomeLabel

var _signup_btn: WoodButton
var _login_btn: WoodButton
var _exit_btn: WoodButton
var _banner: TitleBanner


func _ready() -> void:
	_bg.texture = BG_TEXTURE
	_content.hide()
	_welcome_label.hide()
	_welcome_label.add_theme_font_override("font", PIXEL_FONT)
	_welcome_label.add_theme_font_size_override("font_size", 20)
	_welcome_label.add_theme_color_override("font_color", TEXT_COLOR)

	# Session restore path
	if Global.load_session():
		_welcome_label.text = "Welcome back, %s!" % Global.display_name
		_welcome_label.show()
		_welcome_label.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(_welcome_label, "modulate:a", 1.0, 0.4)
		await tw.finished
		await get_tree().create_timer(1.8).timeout
		SceneManager.goto_map_selection()
		return

	_build_ui()
	_play_entrance()


func _build_ui() -> void:
	# Title banner
	_banner = TitleBanner.new()
	_banner.custom_minimum_size = Vector2(400, 100)
	_content.add_child(_banner)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	_content.add_child(spacer)

	# Sign Up button
	_signup_btn = WoodButton.new()
	_signup_btn.text = "Sign Up"
	_signup_btn.icon_type = "key"
	_signup_btn.custom_minimum_size = Vector2(320, 52)
	_signup_btn.pressed.connect(_on_signup)
	_content.add_child(_signup_btn)

	# Log In button
	_login_btn = WoodButton.new()
	_login_btn.text = "Log In"
	_login_btn.icon_type = "lock"
	_login_btn.custom_minimum_size = Vector2(320, 52)
	_login_btn.pressed.connect(_on_login)
	_content.add_child(_login_btn)

	# Exit button
	_exit_btn = WoodButton.new()
	_exit_btn.text = "Exit"
	_exit_btn.custom_minimum_size = Vector2(320, 52)
	_exit_btn.pressed.connect(_on_exit)
	_content.add_child(_exit_btn)


func _play_entrance() -> void:
	_content.show()

	# Start everything invisible
	_banner.modulate.a = 0.0
	_signup_btn.modulate.a = 0.0
	_login_btn.modulate.a = 0.0
	_exit_btn.modulate.a = 0.0

	# Title banner fades in first
	var tw := create_tween()
	tw.tween_property(_banner, "modulate:a", 1.0, 0.5).set_ease(Tween.EASE_OUT)

	# After 200ms Sign Up fades in
	tw.tween_interval(0.2)
	tw.tween_property(_signup_btn, "modulate:a", 1.0, 0.35).set_ease(Tween.EASE_OUT)

	# After another 100ms Log In fades in
	tw.tween_interval(0.1)
	tw.tween_property(_login_btn, "modulate:a", 1.0, 0.35).set_ease(Tween.EASE_OUT)

	# After another 100ms Exit fades in
	tw.tween_interval(0.1)
	tw.tween_property(_exit_btn, "modulate:a", 1.0, 0.35).set_ease(Tween.EASE_OUT)


func _on_signup() -> void:
	SceneManager.goto_signup()


func _on_login() -> void:
	SceneManager.goto_login()


func _on_exit() -> void:
	get_tree().quit()
