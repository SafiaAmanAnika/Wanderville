extends Control

const PIXEL_FONT := preload("res://Assets/fonts/BoldPixels.ttf")
const BG_TEXTURE := preload("res://Assets/background/bg.png")

const TEXT_SUCCESS := Color(0.50, 0.78, 0.45)

@onready var _bg: TextureRect = %Background
@onready var _panel: PanelContainer = %FormPanel
@onready var _title: Label = %Title
@onready var _username: LineEdit = %UsernameInput
@onready var _password: LineEdit = %PasswordInput
@onready var _error_label: Label = %ErrorLabel
@onready var _loading_label: Label = %LoadingLabel
@onready var _login_btn: WoodButton = %LoginBtn
@onready var _google_btn: WoodButton = %GoogleBtn
@onready var _forgot_btn: WoodButton = %ForgotBtn
@onready var _back_btn: WoodButton = %BackBtn

var _all_fields: Array[LineEdit]


func _ready() -> void:
	_bg.texture = BG_TEXTURE

	WoodPanel.apply_title_style(_title)
	WoodPanel.apply_field_style(_username)
	WoodPanel.apply_field_style(_password)
	WoodPanel.apply_status_label(_error_label)
	WoodPanel.apply_status_label(_loading_label)

	_all_fields = [_username, _password]

	_login_btn.pressed.connect(_on_login)
	_google_btn.pressed.connect(_on_google)
	_forgot_btn.pressed.connect(_on_forgot)
	_back_btn.pressed.connect(_on_back)
	_password.text_submitted.connect(func(_t: String) -> void: _on_login())

	_error_label.text = " "
	_loading_label.text = " "

	if Global.load_session():
		_loading_label.text = "Restoring session..."
		_set_busy(true)
		var me_res := await APIClient.me(Global.token)
		if bool(me_res.get("ok", false)):
			SceneManager.goto_post_login()
			return
		else:
			Global.clear_session()
			_loading_label.text = " "
			_set_busy(false)

	_username.grab_focus()
	WoodPanel.play_entrance(_panel)


func _set_busy(busy: bool) -> void:
	_login_btn.disabled = busy
	_google_btn.disabled = busy
	_forgot_btn.disabled = busy
	_back_btn.disabled = busy
	_username.editable = not busy
	_password.editable = not busy


func _clear_errors() -> void:
	_error_label.text = " "
	for f in _all_fields:
		WoodPanel.clear_error_field_style(f)


func _mark_field_error(field: LineEdit) -> void:
	WoodPanel.apply_error_field_style(field)


func _on_login() -> void:
	var u := _username.text.strip_edges()
	var p := _password.text

	_clear_errors()

	if u == "" or p == "":
		_error_label.text = "Enter username and password."
		if u == "":
			_mark_field_error(_username)
			_username.grab_focus()
		else:
			_mark_field_error(_password)
			_password.grab_focus()
		return

	_set_busy(true)
	_loading_label.text = "Logging in..."
	_error_label.text = " "

	var res: Dictionary = await APIClient.login(u, p)

	if not bool(res.get("ok", false)):
		_set_busy(false)
		_loading_label.text = " "
		_handle_login_error(res)
		return

	var body: Variant = res.get("body")
	if typeof(body) != TYPE_DICTIONARY:
		_set_busy(false)
		_loading_label.text = " "
		_error_label.text = "Unexpected response from server."
		return

	var data: Dictionary = body.get("data", {})
	var token: String = str(data.get("access_token", ""))
	var new_refresh: String = str(data.get("refresh_token", ""))
	var player: Dictionary = data.get("player", {})

	if token == "" or player.is_empty():
		_set_busy(false)
		_loading_label.text = " "
		_error_label.text = "Login succeeded but response was incomplete."
		return

	Global.set_session(token, player, new_refresh)

	var me_res: Dictionary = await APIClient.me(Global.token)
	if not bool(me_res.get("ok", false)):
		_error_label.text = "Logged in, but profile fetch failed."
		_set_busy(false)
		_loading_label.text = " "
		return

	_loading_label.text = "Loading..."
	await GameState.load_from_backend()
	await get_tree().create_timer(1.0).timeout
	SceneManager.goto_post_login()


func _on_google() -> void:
	_set_busy(true)
	_loading_label.text = "Opening Google Sign-In..."
	_error_label.text = " "

	var url := APIClient.base_url + "/auth/google/redirect"
	OS.shell_open(url)

	await get_tree().create_timer(3.0).timeout
	_set_busy(false)
	_loading_label.text = " "
	_error_label.text = "Please complete Google Sign-In in your browser, then open the game from the link provided."


func _handle_login_error(res: Dictionary) -> void:
	var body: Variant = res.get("body")
	if typeof(body) == TYPE_DICTIONARY:
		var err := str(body.get("error", ""))
		if err == "ACCOUNT_LOCKED":
			_error_label.text = "Account is temporarily locked. Please try again later."
			return
		elif err == "EMAIL_NOT_VERIFIED":
			_error_label.text = "Please verify your email first."
			_mark_field_error(_username)
			return

	_mark_field_error(_username)
	_mark_field_error(_password)
	_password.text = ""
	_password.grab_focus()
	_error_label.text = _format_error(res)


func _on_forgot() -> void:
	SceneManager.goto_forgot_password()


func _on_back() -> void:
	SceneManager.goto_title()


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
