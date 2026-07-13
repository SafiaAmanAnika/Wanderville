extends Control

const PIXEL_FONT := preload("res://Assets/fonts/BoldPixels.ttf")
const BG_TEXTURE := preload("res://Assets/background/bg.png")

const TEXT_SUCCESS := Color(0.50, 0.78, 0.45)
const TEXT_FAIL := Color(0.90, 0.38, 0.30)
const TEXT_SECONDARY := Color(0.82, 0.74, 0.58)
const TEXT_WEAK := Color(0.85, 0.45, 0.30)
const TEXT_MEDIUM := Color(0.85, 0.75, 0.35)
const TEXT_STRONG := Color(0.45, 0.75, 0.40)

@onready var _bg: TextureRect = %Background

# Form nodes
@onready var _form_panel: PanelContainer = %FormPanel
@onready var _title: Label = %Title
@onready var _password: LineEdit = %PasswordInput
@onready var _strength: Label = %PasswordStrength
@onready var _confirm: LineEdit = %ConfirmInput
@onready var _error_label: Label = %ErrorLabel
@onready var _loading_label: Label = %LoadingLabel
@onready var _reset_btn: WoodButton = %ResetBtn
@onready var _back_btn: WoodButton = %BackBtn

# Success panel
@onready var _success_panel: PanelContainer = %SuccessPanel
@onready var _success_title: Label = %SuccessTitle
@onready var _success_message: Label = %SuccessMessage
@onready var _back_to_login_btn: WoodButton = %BackToLoginBtn

# Error panel (for invalid token)
@onready var _error_panel: PanelContainer = %ErrorPanel
@onready var _error_title: Label = %ErrorTitle
@onready var _error_message_label: Label = %ErrorMessageLabel
@onready var _error_login_btn: WoodButton = %ErrorLoginBtn

var _token: String = ""
var _re_upper: RegEx
var _re_lower: RegEx
var _re_digit: RegEx
var _re_special: RegEx


func _ready() -> void:
	_bg.texture = BG_TEXTURE

	WoodPanel.apply_title_style(_title)
	WoodPanel.apply_field_style(_password)
	WoodPanel.apply_field_style(_confirm)
	WoodPanel.apply_status_label(_error_label)
	WoodPanel.apply_status_label(_loading_label)

	_apply_strength_style()
	_apply_success_style()
	_apply_error_panel_style()

	_re_upper = RegEx.new(); _re_upper.compile("[A-Z]")
	_re_lower = RegEx.new(); _re_lower.compile("[a-z]")
	_re_digit = RegEx.new(); _re_digit.compile("\\d")
	_re_special = RegEx.new(); _re_special.compile("[!@#$%^&*()_+\\-=\\[\\]{};:'\",.<>?/\\\\|`~]")

	_reset_btn.pressed.connect(_on_reset)
	_back_btn.pressed.connect(_on_back)
	_confirm.text_submitted.connect(func(_t: String) -> void: _on_reset())
	_password.text_changed.connect(_on_password_changed)
	_back_to_login_btn.pressed.connect(_on_back)
	_error_login_btn.pressed.connect(_on_back)

	_error_label.text = " "
	_loading_label.text = " "
	_strength.text = " "

	_success_panel.hide()
	_error_panel.hide()
	_form_panel.show()

	_token = Global.pending_reset_token
	Global.pending_reset_token = ""

	if _token == "":
		_show_error_panel("No Reset Token", "No password reset token was provided. Please request a new reset link.")
		return

	_password.grab_focus()
	WoodPanel.play_entrance(_form_panel)


func _apply_strength_style() -> void:
	_strength.add_theme_font_override("font", PIXEL_FONT)
	_strength.add_theme_font_size_override("font_size", WoodPanel.SIZE_SMALL)
	_strength.add_theme_color_override("font_color", TEXT_SECONDARY)
	_strength.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _apply_success_style() -> void:
	WoodPanel.apply_panel_title_style(_success_title)

	_success_message.add_theme_font_override("font", PIXEL_FONT)
	_success_message.add_theme_font_size_override("font_size", WoodPanel.SIZE_STATUS)
	_success_message.add_theme_color_override("font_color", TEXT_SUCCESS)
	_success_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_success_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _apply_error_panel_style() -> void:
	WoodPanel.apply_panel_title_style(_error_title)

	_error_message_label.add_theme_font_override("font", PIXEL_FONT)
	_error_message_label.add_theme_font_size_override("font_size", WoodPanel.SIZE_STATUS)
	_error_message_label.add_theme_color_override("font_color", TEXT_FAIL)
	_error_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _on_password_changed(_new_text: String) -> void:
	var p := _password.text
	if p.is_empty():
		_strength.text = " "
		return

	var score := 0
	if p.length() >= 8:
		score += 1
	if _re_upper.search(p):
		score += 1
	if _re_lower.search(p):
		score += 1
	if _re_digit.search(p):
		score += 1
	if _re_special.search(p):
		score += 1

	match score:
		0, 1:
			_strength.text = "Very Weak"
			_strength.add_theme_color_override("font_color", TEXT_WEAK)
		2:
			_strength.text = "Weak"
			_strength.add_theme_color_override("font_color", TEXT_WEAK)
		3:
			_strength.text = "Fair"
			_strength.add_theme_color_override("font_color", TEXT_MEDIUM)
		4:
			_strength.text = "Strong"
			_strength.add_theme_color_override("font_color", TEXT_STRONG)
		5:
			_strength.text = "Very Strong"
			_strength.add_theme_color_override("font_color", TEXT_STRONG)


func _set_busy(busy: bool) -> void:
	_reset_btn.disabled = busy
	_back_btn.disabled = busy
	_password.editable = not busy
	_confirm.editable = not busy


func _on_reset() -> void:
	var p := _password.text
	var c := _confirm.text

	_error_label.text = " "

	if p == "":
		_error_label.text = "Please enter a new password."
		WoodPanel.apply_error_field_style(_password)
		_password.grab_focus()
		return

	if p.length() < 8:
		_error_label.text = "Password must be at least 8 characters."
		WoodPanel.apply_error_field_style(_password)
		_password.text = ""
		_password.grab_focus()
		return

	if p != c:
		_error_label.text = "Passwords do not match."
		WoodPanel.apply_error_field_style(_confirm)
		_confirm.text = ""
		_confirm.grab_focus()
		return

	WoodPanel.clear_error_field_style(_password)
	WoodPanel.clear_error_field_style(_confirm)
	_set_busy(true)
	_loading_label.text = "Resetting password..."

	var res: Dictionary = await APIClient.reset_password(_token, p)
	_set_busy(false)
	_loading_label.text = " "

	if not bool(res.get("ok", false)):
		var body: Variant = res.get("body")
		if typeof(body) == TYPE_DICTIONARY:
			var err := str(body.get("error", ""))
			if err == "TOKEN_EXPIRED":
				_show_error_panel("Link Expired", "This password reset link has expired. Please request a new one.")
				return
			elif err == "INVALID_TOKEN":
				_show_error_panel("Invalid Link", "This password reset link is invalid.")
				return
		_error_label.text = _format_error(res)
		return

	_form_panel.hide()
	_success_panel.show()
	_success_title.text = "Password Reset"
	_success_message.text = "Your password has been reset successfully.\nPlease log in with your new password."
	WoodPanel.play_entrance(_success_panel)


func _show_error_panel(title: String, message: String) -> void:
	_form_panel.hide()
	_success_panel.hide()
	_error_panel.show()
	_error_title.text = title
	_error_message_label.text = message
	WoodPanel.play_entrance(_error_panel)


func _on_back() -> void:
	SceneManager.goto_login()


func _format_error(res: Dictionary) -> String:
	var body: Variant = res.get("body")
	if typeof(body) == TYPE_DICTIONARY:
		var msg := str(body.get("message", ""))
		var err := str(body.get("error", ""))
		if msg != "" and err != "":
			return "%s (%s)" % [msg, err]
		if msg != "":
			return msg
		if err != "":
			return err
	var status_code := int(res.get("status_code", 0))
	return "Request failed (HTTP %d)." % status_code
