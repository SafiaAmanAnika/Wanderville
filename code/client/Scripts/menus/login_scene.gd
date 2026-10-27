extends Control

const AuthShell := preload("res://Scripts/menus/auth_shell.gd")

const PIXEL_FONT := preload("res://Assets/fonts/BoldPixels.ttf")
const BG_TEXTURE := preload("res://Assets/background/bg.png")

const TEXT_SUCCESS := Color("4d6c43")

@onready var _bg: TextureRect = %Background
@onready var _panel: PanelContainer = %FormPanel
@onready var _title: Label = %Title
@onready var _username: LineEdit = %UsernameInput
@onready var _password: LineEdit = %PasswordInput
@onready var _error_label: Label = %ErrorLabel
@onready var _loading_label: Label = %LoadingLabel
@onready var _login_btn: Button = %LoginBtn
@onready var _google_btn: Button = %GoogleBtn
@onready var _forgot_btn: Button = %ForgotBtn
@onready var _back_btn: Button = %BackBtn

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

	_username.grab_focus()
	AuthShell.reveal(_panel)

	AuthShell.install(self)


func _set_busy(busy: bool) -> void:
	var create_link := find_child("CreateAccountLink",true,false) as Button
	if create_link != null: create_link.disabled = busy
	_login_btn.disabled = busy
	_google_btn.disabled = busy
	_forgot_btn.disabled = busy
	_back_btn.disabled = busy
	_username.editable = not busy
	_password.editable = not busy


func _clear_errors() -> void:
	_error_label.text = " "
	for f in _all_fields:
		AuthShell.clear_field(f)


func _mark_field_error(field: LineEdit) -> void:
	AuthShell.field_error(field)


func _on_login() -> void:
	if _login_btn.disabled: return
	var u := _username.text.strip_edges()
	var p := _password.text

	_clear_errors()

	if u == "" or p == "":
		_error_label.text = "Enter your username or email and password."
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
	await _finish_login(res)


func _finish_login(res: Dictionary) -> void:

	if not bool(res.get("ok", false)):
		_set_busy(false)
		_loading_label.text = " "
		_handle_login_error(res)
		return

	var loaded: Dictionary = await preload("res://Scripts/menus/auth_flow.gd").complete(res)
	if not loaded.get("ok",false):
		_set_busy(false)
		_loading_label.text = " "
		_error_label.text = APIClient.error_text(loaded)
		return
	SceneManager.goto_post_login()


func _on_google() -> void:
	if _google_btn.disabled: return
	_set_busy(true)
	_loading_label.text = "Opening Google Sign-In..."
	_error_label.text = " "

	var response: Dictionary = await APIClient.google_browser_login()
	if not bool(response.get("ok", false)):
		_set_busy(false)
		_loading_label.text = " "
		# A Google failure says nothing about the username/password fields.
		_error_label.text = _format_error(response)
		return
	await _finish_login(response)


func _handle_login_error(res: Dictionary) -> void:
	var body: Variant = res.get("body")
	if typeof(body) == TYPE_DICTIONARY:
		var err := str(body.get("error", ""))
		if err in ["ACCOUNT_LOCKED", "ACCOUNT_internal"]:
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
	return APIClient.error_text(res) if status_code == 0 else "Request failed (HTTP %d)." % status_code
