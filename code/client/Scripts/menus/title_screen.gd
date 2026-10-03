extends Control

const PIXEL_FONT := preload("res://Assets/fonts/BoldPixels.ttf")
const BG_TEXTURE := preload("res://Assets/background/bg.png")

const TEXT_COLOR := Color(0.95, 0.91, 0.80)
const TEXT_SECONDARY := Color(0.82, 0.74, 0.58)

@onready var _bg: TextureRect = %Background
@onready var _content: VBoxContainer = %Content
@onready var _welcome_panel: PanelContainer = %WelcomePanel
@onready var _welcome_label: Label = %WelcomeLabel
@onready var _loading_bar: ProgressBar = %LoadingBar
@onready var _loading_label: Label = %LoadingLabel

var _signup_btn: WoodButton
var _login_btn: WoodButton
var _exit_btn: WoodButton
var _banner: TitleBanner


func _ready() -> void:
	_bg.texture = BG_TEXTURE
	_content.hide()
	_welcome_panel.hide()
	_loading_bar.hide()
	_loading_label.hide()

	_welcome_label.add_theme_font_override("font", PIXEL_FONT)
	_welcome_label.add_theme_font_size_override("font_size", WoodPanel.SIZE_PANEL_TITLE)
	_welcome_label.add_theme_color_override("font_color", TEXT_COLOR)
	_welcome_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_loading_label.add_theme_font_override("font", PIXEL_FONT)
	_loading_label.add_theme_font_size_override("font_size", WoodPanel.SIZE_STATUS)
	_loading_label.add_theme_color_override("font_color", TEXT_SECONDARY)
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_apply_loading_bar_style()

	# Deep link routing
	if Global.pending_verify_token != "":
		SceneManager.goto_email_verification()
		return
	if Global.pending_reset_token != "":
		SceneManager.goto_reset_password(Global.pending_reset_token)
		return

	# Session restore path
	if Global.load_session():
		_show_welcome_and_load()
		return

	_build_ui()
	_play_entrance()


func _apply_loading_bar_style() -> void:
	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color = Color(0.22, 0.15, 0.08)
	bg_sb.set_corner_radius_all(4)
	bg_sb.set_border_width_all(2)
	bg_sb.border_color = Color(0.38, 0.25, 0.13)
	bg_sb.content_margin_left = 2
	bg_sb.content_margin_right = 2
	bg_sb.content_margin_top = 2
	bg_sb.content_margin_bottom = 2
	_loading_bar.add_theme_stylebox_override("background", bg_sb)

	var fill_sb := StyleBoxFlat.new()
	fill_sb.bg_color = Color(0.60, 0.78, 0.35)
	fill_sb.set_corner_radius_all(3)
	_loading_bar.add_theme_stylebox_override("fill", fill_sb)


func _show_welcome_and_load() -> void:
	_welcome_panel.show()
	_welcome_label.text = "Welcome back, %s!" % Global.display_name
	_welcome_label.modulate.a = 0.0
	_welcome_panel.modulate.a = 0.0

	var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_welcome_panel, "modulate:a", 1.0, 0.4)
	tw.parallel().tween_property(_welcome_label, "modulate:a", 1.0, 0.5)
	await tw.finished

	# Show loading bar
	_loading_bar.show()
	_loading_label.show()
	_loading_bar.value = 0.0
	_loading_bar.modulate.a = 0.0
	_loading_label.modulate.a = 0.0
	var tw2 := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw2.tween_property(_loading_bar, "modulate:a", 1.0, 0.3)
	tw2.parallel().tween_property(_loading_label, "modulate:a", 1.0, 0.3)

	# Animate loading bar
	_loading_label.text = "Loading..."
	var bar_tween := create_tween()
	bar_tween.tween_property(_loading_bar, "value", 30.0, 0.3)
	bar_tween.tween_interval(0.2)
	bar_tween.tween_property(_loading_bar, "value", 60.0, 0.3)

	var response: Dictionary = await APIClient.me(Global.token)
	if not bool(response.get("ok", false)):
		bar_tween.kill()
		if int(response.get("status_code", 0)) == 401:
			Global.clear_session()
		SceneManager.goto_login()
		return
	bar_tween.kill()
	_loading_bar.value = 80.0

	if not await GameState.load_from_backend():
		SceneManager.goto_login()
		return
	_loading_bar.value = 100.0
	_loading_label.text = "Ready!"

	await get_tree().create_timer(0.4).timeout
	SceneManager.goto_post_login()


func _build_ui() -> void:
	_banner = TitleBanner.new()
	_banner.custom_minimum_size = Vector2(460, 100)
	_content.add_child(_banner)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	_content.add_child(spacer)

	_signup_btn = WoodButton.new()
	_signup_btn.text = "Sign Up"
	_signup_btn.icon_type = "key"
	_signup_btn.custom_minimum_size = Vector2(360, 58)
	_signup_btn.pressed.connect(_on_signup)
	_content.add_child(_signup_btn)

	_login_btn = WoodButton.new()
	_login_btn.text = "Log In"
	_login_btn.icon_type = "lock"
	_login_btn.custom_minimum_size = Vector2(360, 58)
	_login_btn.pressed.connect(_on_login)
	_content.add_child(_login_btn)

	_exit_btn = WoodButton.new()
	_exit_btn.text = "Exit"
	_exit_btn.custom_minimum_size = Vector2(360, 58)
	_exit_btn.pressed.connect(_on_exit)
	_content.add_child(_exit_btn)


func _play_entrance() -> void:
	_content.show()

	_banner.modulate.a = 0.0
	_signup_btn.modulate.a = 0.0
	_login_btn.modulate.a = 0.0
	_exit_btn.modulate.a = 0.0

	var tw := create_tween()
	tw.tween_property(_banner, "modulate:a", 1.0, 0.5).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.2)
	tw.tween_property(_signup_btn, "modulate:a", 1.0, 0.35).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.1)
	tw.tween_property(_login_btn, "modulate:a", 1.0, 0.35).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.1)
	tw.tween_property(_exit_btn, "modulate:a", 1.0, 0.35).set_ease(Tween.EASE_OUT)


func _on_signup() -> void:
	SceneManager.goto_signup()


func _on_login() -> void:
	SceneManager.goto_login()


func _on_exit() -> void:
	get_tree().quit()
