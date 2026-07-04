extends Control

@onready var _username: LineEdit = $Center/Panel/VBox/UsernameInput
@onready var _display_name: LineEdit = $Center/Panel/VBox/DisplayNameInput
@onready var _password: LineEdit = $Center/Panel/VBox/PasswordInput
@onready var _status: Label = $Center/Panel/VBox/StatusLabel
@onready var _create_button: Button = $Center/Panel/VBox/Buttons/SignupButton
@onready var _back_button: Button = $Center/Panel/VBox/Buttons/BackToLoginButton

var _lineedits: Array[LineEdit]
var _error_style: StyleBoxFlat


func _ready() -> void:
	_create_button.pressed.connect(_on_create_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_status.text = ""
	_username.grab_focus()
	_lineedits = [_username, _display_name, _password]
	_build_error_style()
	_clear_error_styles()


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


func _set_busy(busy: bool) -> void:
	_create_button.disabled = busy
	_back_button.disabled = busy
	_username.editable = not busy
	_display_name.editable = not busy
	_password.editable = not busy


func _clear_error_styles() -> void:
	for le in _lineedits:
		le.remove_theme_stylebox_override("normal")


func _mark_error(edit: LineEdit) -> void:
	edit.add_theme_stylebox_override("normal", _error_style)


func _on_back_pressed() -> void:
	SceneManager.goto_title()


func _on_create_pressed() -> void:
	var u := _username.text.strip_edges()
	var d := _display_name.text.strip_edges()
	var p := _password.text

	_clear_error_styles()

	if u == "" or d == "" or p == "":
		_status.text = "Please fill in all fields."
		if u == "":
			_mark_error(_username)
			_username.grab_focus()
		elif d == "":
			_mark_error(_display_name)
			_display_name.grab_focus()
		else:
			_mark_error(_password)
			_password.grab_focus()
		return

	if p.length() < 6:
		_mark_error(_password)
		_password.text = ""
		_password.grab_focus()
		_status.text = "Password must be at least 6 letters."
		return

	_set_busy(true)
	_status.text = "Creating account..."
	var res: Dictionary = await APIClient.signup(u, p, d)
	_set_busy(false)

	if not bool(res.get("ok", false)):
		var body = res.get("body")
		if typeof(body) == TYPE_DICTIONARY:
			var err = str(body.get("error", ""))
			if err == "USERNAME_TAKEN":
				_mark_error(_username)
				_password.text = ""
				_username.grab_focus()
				_status.text = "That username is already taken."
				return
		_status.text = _format_error(res)
		return

	_status.text = "Account created! Logging you in..."
	_set_busy(true)
	var login_res := await APIClient.login(u, p)
	_set_busy(false)

	if bool(login_res.get("ok", false)):
		var lbody = login_res.get("body")
		if typeof(lbody) == TYPE_DICTIONARY:
			var data = lbody.get("data", {})
			var token = str(data.get("token", ""))
			var player = data.get("player", {})
			if token != "" and not player.is_empty():
				Global.set_session(token, player)
				await get_tree().create_timer(0.5).timeout
				SceneManager.goto_map_selection()
				return

	_status.text = "Account created. Please log in manually."


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
