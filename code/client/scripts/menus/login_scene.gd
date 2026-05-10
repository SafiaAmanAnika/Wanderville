extends Control

@onready var _username: LineEdit = $Center/Panel/VBox/UsernameInput
@onready var _password: LineEdit = $Center/Panel/VBox/PasswordInput
@onready var _status: Label = $Center/Panel/VBox/StatusLabel
@onready var _login_button: Button = $Center/Panel/VBox/Buttons/LoginButton
@onready var _signup_button: Button = $Center/Panel/VBox/Buttons/GoToSignupButton


func _ready() -> void:
	_login_button.pressed.connect(_on_login_pressed)
	_signup_button.pressed.connect(_on_signup_pressed)
	_status.text = ""

	# Quality-of-life: allow Enter to submit.
	_password.text_submitted.connect(func(_t: String) -> void: _on_login_pressed())
	_username.grab_focus()


func _set_busy(busy: bool) -> void:
	_login_button.disabled = busy
	_signup_button.disabled = busy
	_username.editable = not busy
	_password.editable = not busy


func _on_signup_pressed() -> void:
	SceneManager.goto_signup()


func _on_login_pressed() -> void:
	var u := _username.text.strip_edges()
	var p := _password.text
	if u == "" or p == "":
		_status.text = "Enter username and password."
		return

	_set_busy(true)
	_status.text = "Logging in..."

	var res: Dictionary = await APIClient.login(u, p)
	_set_busy(false)

	if not bool(res.get("ok", false)):
		_status.text = _format_error(res)
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

	Global.set_session(token, player)

	# Optional sanity check that the token works.
	var me_res: Dictionary = await APIClient.me(Global.token)
	if not bool(me_res.get("ok", false)):
		_status.text = "Logged in, but /auth/me failed. Token may be invalid."
		return

	_status.text = "Logged in successfully. MainWorld is not created yet."


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
