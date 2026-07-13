extends Control

const PIXEL_FONT := preload("res://Assets/fonts/BoldPixels.ttf")
const BG_TEXTURE := preload("res://Assets/background/bg.png")

const TEXT_SECONDARY := Color(0.82, 0.74, 0.58)
const TEXT_WEAK := Color(0.85, 0.45, 0.30)
const TEXT_MEDIUM := Color(0.85, 0.75, 0.35)
const TEXT_STRONG := Color(0.45, 0.75, 0.40)

@onready var _bg: TextureRect = %Background
@onready var _title: Label = %Title
@onready var _username: LineEdit = %UsernameInput
@onready var _email: LineEdit = %EmailInput
@onready var _password: LineEdit = %PasswordInput
@onready var _strength: Label = %PasswordStrength
@onready var _confirm: LineEdit = %ConfirmInput
@onready var _error_label: Label = %ErrorLabel
@onready var _loading_label: Label = %LoadingLabel
@onready var _create_btn: WoodButton = %CreateBtn
@onready var _back_btn: WoodButton = %BackBtn

var _all_fields: Array[LineEdit]
var _re_upper: RegEx
var _re_lower: RegEx
var _re_digit: RegEx
var _re_special: RegEx


func _ready() -> void:
	_bg.texture = BG_TEXTURE

	WoodPanel.apply_title_style(_title)
	WoodPanel.apply_field_style(_username)
	WoodPanel.apply_field_style(_email)
	WoodPanel.apply_field_style(_password)
	WoodPanel.apply_field_style(_confirm)
	WoodPanel.apply_status_label(_error_label)
	WoodPanel.apply_status_label(_loading_label)
	_apply_strength_style()

	_all_fields = [_username, _email, _password, _confirm]

	_re_upper = RegEx.new(); _re_upper.compile("[A-Z]")
	_re_lower = RegEx.new(); _re_lower.compile("[a-z]")
	_re_digit = RegEx.new(); _re_digit.compile("\\d")
	_re_special = RegEx.new(); _re_special.compile("[!@#$%^&*()_+\\-=\\[\\]{};:'\",.<>?/\\\\|`~]")

	_create_btn.pressed.connect(_on_create)
	_back_btn.pressed.connect(_on_back)
	_confirm.text_submitted.connect(func(_t: String) -> void: _on_create())
	_password.text_changed.connect(_on_password_changed)

	_error_label.text = " "
	_loading_label.text = " "
	_strength.text = " "

	_username.grab_focus()
	_play_entrance()


func _apply_strength_style() -> void:
	_strength.add_theme_font_override("font", PIXEL_FONT)
	_strength.add_theme_font_size_override("font_size", 14)
	_strength.add_theme_color_override("font_color", TEXT_SECONDARY)
	_strength.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _play_entrance() -> void:
	var panel: PanelContainer = %FormPanel
	panel.modulate.a = 0.0
	var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(panel, "modulate:a", 1.0, 0.4)


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
	_create_btn.disabled = busy
	_back_btn.disabled = busy
	_username.editable = not busy
	_email.editable = not busy
	_password.editable = not busy
	_confirm.editable = not busy


func _clear_errors() -> void:
	_error_label.text = " "
	for f in _all_fields:
		WoodPanel.clear_error_field_style(f)


func _mark_field_error(field: LineEdit) -> void:
	WoodPanel.apply_error_field_style(field)


func _on_create() -> void:
	var u := _username.text.strip_edges()
	var e := _email.text.strip_edges()
	var p := _password.text
	var c := _confirm.text

	_clear_errors()

	if u == "" or e == "" or p == "" or c == "":
		_error_label.text = "Please fill in all fields."
		if u == "":
			_mark_field_error(_username)
			_username.grab_focus()
		elif e == "":
			_mark_field_error(_email)
			_email.grab_focus()
		elif p == "":
			_mark_field_error(_password)
			_password.grab_focus()
		else:
			_mark_field_error(_confirm)
			_confirm.grab_focus()
		return

	if not e.contains("@") or not e.contains("."):
		_mark_field_error(_email)
		_error_label.text = "Please enter a valid email address."
		_email.grab_focus()
		return

	if p.length() < 8:
		_mark_field_error(_password)
		_password.text = ""
		_password.grab_focus()
		_error_label.text = "Password must be at least 8 characters."
		return

	if p != c:
		_mark_field_error(_confirm)
		_confirm.text = ""
		_confirm.grab_focus()
		_error_label.text = "Passwords do not match."
		return

	_set_busy(true)
	_loading_label.text = "Creating account..."
	_error_label.text = " "

	var res: Dictionary = await APIClient.signup(u, e, p, u)
	_set_busy(false)
	_loading_label.text = " "

	if not bool(res.get("ok", false)):
		var body_v: Variant = res.get("body")
		if typeof(body_v) == TYPE_DICTIONARY:
			var err_code := str(body_v.get("error", ""))
			if err_code == "USERNAME_TAKEN":
				_mark_field_error(_username)
				_username.grab_focus()
				_password.text = ""
				_confirm.text = ""
				_error_label.text = "That username is already taken."
				return
			elif err_code == "EMAIL_TAKEN":
				_mark_field_error(_email)
				_email.grab_focus()
				_error_label.text = "An account with this email already exists."
				return
		_error_label.text = _format_error(res)
		return

	# Signup succeeded — email verification required before login
	SceneManager.goto_email_verification(
		"Account created! Please check your email to verify your account before logging in.",
		true
	)


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
