extends Control

const AuthShell := preload("res://Scripts/menus/auth_shell.gd")

const PIXEL_FONT := preload("res://Assets/fonts/BoldPixels.ttf")
const BG_TEXTURE := preload("res://Assets/background/bg.png")

const TEXT_SECONDARY := Color(0.82, 0.74, 0.58)
const TEXT_SUCCESS := Color("4d6c43")

@onready var _bg: TextureRect = %Background

# Form nodes
@onready var _form_panel: PanelContainer = %FormPanel
@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _email: LineEdit = %EmailInput
@onready var _error_label: Label = %ErrorLabel
@onready var _loading_label: Label = %LoadingLabel
@onready var _send_btn: Button = %SendBtn
@onready var _back_btn: Button = %BackBtn

# Success nodes
@onready var _success_panel: PanelContainer = %SuccessPanel
@onready var _success_title: Label = %SuccessTitle
@onready var _success_message: Label = %SuccessMessage
@onready var _back_to_login_btn: Button = %BackToLoginBtn


func _ready() -> void:
	_bg.texture = BG_TEXTURE

	WoodPanel.apply_title_style(_title)
	WoodPanel.apply_field_style(_email)
	WoodPanel.apply_status_label(_error_label)
	WoodPanel.apply_status_label(_loading_label)

	_apply_subtitle_style()
	_apply_success_style()

	_send_btn.pressed.connect(_on_send)
	_back_btn.pressed.connect(_on_back)
	_email.text_submitted.connect(func(_t: String) -> void: _on_send())
	_back_to_login_btn.pressed.connect(_on_back)

	_error_label.text = " "
	_loading_label.text = " "

	_success_panel.hide()
	_form_panel.show()

	_email.grab_focus()
	AuthShell.reveal(_form_panel)

	AuthShell.install(self)


func _apply_subtitle_style() -> void:
	_subtitle.add_theme_font_override("font", PIXEL_FONT)
	_subtitle.add_theme_font_size_override("font_size", WoodPanel.SIZE_SMALL)
	_subtitle.add_theme_color_override("font_color", TEXT_SECONDARY)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _apply_success_style() -> void:
	WoodPanel.apply_panel_title_style(_success_title)

	_success_message.add_theme_font_override("font", PIXEL_FONT)
	_success_message.add_theme_font_size_override("font_size", WoodPanel.SIZE_STATUS)
	_success_message.add_theme_color_override("font_color", TEXT_SUCCESS)
	_success_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_success_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _set_busy(busy: bool) -> void:
	_send_btn.disabled = busy
	_back_btn.disabled = busy
	_email.editable = not busy


func _on_send() -> void:
	if _send_btn.disabled: return
	var e := _email.text.strip_edges()
	_error_label.text = " "

	if e == "":
		_error_label.text = "Please enter your email address."
		AuthShell.field_error(_email)
		_email.grab_focus()
		return

	if not e.contains("@") or not e.contains("."):
		_error_label.text = "Please enter a valid email address."
		AuthShell.field_error(_email)
		_email.grab_focus()
		return

	AuthShell.clear_field(_email)
	_set_busy(true)
	_loading_label.text = "Sending reset link..."

	var response: Dictionary = await APIClient.forgot_password(e)
	_set_busy(false)
	_loading_label.text = " "
	if not response.get("ok",false):
		_error_label.text = APIClient.error_text(response)
		return

	_form_panel.hide()
	_success_panel.show()
	_success_message.text = "Please check your email for\npassword reset instructions."
	AuthShell.reveal(_success_panel)


func _on_back() -> void:
	SceneManager.goto_login()
