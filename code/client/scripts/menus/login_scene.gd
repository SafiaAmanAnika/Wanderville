extends Control

@onready var _username: LineEdit = $Center/Panel/VBox/UsernameInput
@onready var _password: LineEdit = $Center/Panel/VBox/PasswordInput
@onready var _status: Label = $Center/Panel/VBox/StatusLabel
@onready var _login_button: Button = $Center/Panel/VBox/Buttons/LoginButton
@onready var _signup_button: Button = $Center/Panel/VBox/Buttons/GoToSignupButton
@onready var _back_button: Button = $Center/Panel/VBox/BackButton
@onready var _remember_check: CheckBox = $Center/Panel/VBox/RememberBox

var _lineedits: Array[LineEdit]
var _error_style: StyleBoxFlat


func _ready() -> void:
	_login_button.pressed.connect(_on_login_pressed)
	_signup_button.pressed.connect(_on_signup_pressed)
	if _back_button:
		_back_button.pressed.connect(_on_back_pressed)
	_status.text = ""
	_password.text_submitted.connect(func(_t: String) -> void: _on_login_pressed())
	_lineedits = [_username, _password]
	_build_error_style()

	if Global.load_session():
		_status.text = "Restoring session..."
		var me_res := await APIClient.me(Global.token)
		if bool(me_res.get("ok", false)):
			SceneManager.goto_map_selection()
			return
		else:
			Global.clear_session()
			_status.text = "Session expired. Please log in again."

	if _remember_check:
		_remember_check.button_pressed = Global.remember_device

	_username.grab_focus()


func _build_error_style() -> void:
	_error_style = StyleBoxFlat.new()
	_error_style.bg_color = Color(0.39, 0.43, 0.45, 1)
	_error_style.border_width_left = 2
	_error_style.border_width_right = 2
	_error_style.border_width_top = 2
	_error_style.border_width_bottom = 2
	_error_style.border_color = Color(0.84, 0.19, 0.19, 1)
	_error_style.corner_radius_top_left = 4
	_error_style.corner_radius_top_right = 4
	_error_style.corner_radius_bottom_right = 4
	_error_style.corner_radius_bottom_left = 4


func _clear_error_styles() -> void:
	for le in _lineedits:
		le.remove_theme_stylebox_override("normal")


func _mark_error(edit: LineEdit) -> void:
	edit.add_theme_stylebox_override("normal", _error_style)


func _set_busy(busy: bool) -> void:
	_login_button.disabled = busy
	_signup_button.disabled = busy
	_username.editable = not busy
	_password.editable = not busy


func _on_signup_pressed() -> void:
	SceneManager.goto_signup()


func _on_back_pressed() -> void:
	SceneManager.goto_title()


func _on_login_pressed() -> void:
	var u := _username.text.strip_edges()
	var p := _password.text

	_clear_error_styles()

	if u == "" or p == "":
		_status.text = "Enter username and password."
		if u == "":
			_mark_error(_username)
			_username.grab_focus()
		else:
			_mark_error(_password)
			_password.grab_focus()
		return

	_set_busy(true)
	_status.text = "Logging in..."

	var res: Dictionary = await APIClient.login(u, p)
	_set_busy(false)

	if not bool(res.get("ok", false)):
		_mark_error(_username)
		_mark_error(_password)
		_password.text = ""
		_password.grab_focus()
		_status.text = "Wrong username or password."
		return

	var body: Variant = res.get("body")
	if typeof(body) != TYPE_DICTIONARY:
		_status.text = "Unexpected response from server."
		return

	var data: Dictionary = body.get("data", {})
	var token: String = str(data.get("token", ""))
	var player: Dictionary = data.get("player", {})
	if token == "" or player.is_empty():
		_status.text = "Login succeeded but response was missing token/player."
		return

	if _remember_check:
		Global.remember_device = _remember_check.button_pressed

	Global.set_session(token, player)

	var me_res: Dictionary = await APIClient.me(Global.token)
	if not bool(me_res.get("ok", false)):
		_status.text = "Logged in, but /auth/me failed. Token may be invalid."
		return

	_status.text = "Loading village..."

	await GameState.load_from_backend()

	var timeout := get_tree().create_timer(5.0)
	await timeout.timeout

	SceneManager.goto_map_selection()


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
	var raw := str(res.get("raw_text", ""))
	if raw != "":
		return "HTTP %d: %s" % [status_code, raw]
	return "Request failed (HTTP %d)." % status_code
