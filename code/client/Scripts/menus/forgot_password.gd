extends Control

const PIXEL_FONT := preload("res://Assets/fonts/BoldPixels.ttf")
const BG_TEXTURE := preload("res://Assets/background/bg.png")

const TEXT_SECONDARY := Color(0.82, 0.74, 0.58)

@onready var _bg: TextureRect = %Background
@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _email: LineEdit = %EmailInput
@onready var _error_label: Label = %ErrorLabel
@onready var _loading_label: Label = %LoadingLabel
@onready var _send_btn: WoodButton = %SendBtn
@onready var _back_btn: WoodButton = %BackBtn


func _ready() -> void:
	_bg.texture = BG_TEXTURE

	WoodPanel.apply_title_style(_title)
	WoodPanel.apply_field_style(_email)
	WoodPanel.apply_status_label(_error_label)
	WoodPanel.apply_status_label(_loading_label)

	_subtitle.add_theme_font_override("font", PIXEL_FONT)
	_subtitle.add_theme_font_size_override("font_size", 9)
	_subtitle.add_theme_color_override("font_color", TEXT_SECONDARY)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_send_btn.pressed.connect(_on_send)
	_back_btn.pressed.connect(_on_back)
	_email.text_submitted.connect(func(_t: String) -> void: _on_send())

	_error_label.text = " "
	_loading_label.text = " "

	_email.grab_focus()
	_play_entrance()


func _play_entrance() -> void:
	var panel: PanelContainer = %FormPanel
	panel.modulate.a = 0.0
	var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(panel, "modulate:a", 1.0, 0.4)


func _set_busy(busy: bool) -> void:
	_send_btn.disabled = busy
	_back_btn.disabled = busy
	_email.editable = not busy


func _on_send() -> void:
	var e := _email.text.strip_edges()
	_error_label.text = " "

	if e == "":
		_error_label.text = "Please enter your email address."
		WoodPanel.apply_error_field_style(_email)
		_email.grab_focus()
		return

	if not e.contains("@") or not e.contains("."):
		_error_label.text = "Please enter a valid email address."
		WoodPanel.apply_error_field_style(_email)
		_email.grab_focus()
		return

	WoodPanel.clear_error_field_style(_email)
	_set_busy(true)
	_loading_label.text = "Sending reset link..."

	var _res: Dictionary = await APIClient.forgot_password(e)
	_set_busy(false)
	_loading_label.text = " "

	SceneManager.goto_email_verification(
		"If that email is registered, a password reset link has been sent.",
		true
	)


func _on_back() -> void:
	SceneManager.goto_login()
