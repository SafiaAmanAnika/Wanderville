extends Control

const PIXEL_FONT := preload("res://Assets/fonts/BoldPixels.ttf")
const BG_TEXTURE := preload("res://Assets/background/bg.png")

const TEXT_SUCCESS := Color(0.50, 0.78, 0.45)
const TEXT_FAIL := Color(0.90, 0.38, 0.30)
const TEXT_WARNING := Color(0.85, 0.75, 0.35)

@onready var _bg: TextureRect = %Background
@onready var _panel: PanelContainer = %FormPanel
@onready var _title: Label = %Title
@onready var _message: Label = %MessageLabel
@onready var _continue_btn: WoodButton = %ContinueBtn
@onready var _resend_btn: WoodButton = %ResendBtn
@onready var _loading_label: Label = %LoadingLabel

var _user_email: String = ""


func _ready() -> void:
	_bg.texture = BG_TEXTURE

	WoodPanel.apply_title_style(_title)
	WoodPanel.apply_status_label(_loading_label)

	_message.add_theme_font_override("font", PIXEL_FONT)
	_message.add_theme_font_size_override("font_size", WoodPanel.SIZE_STATUS)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_continue_btn.pressed.connect(_on_continue)
	_resend_btn.pressed.connect(_on_resend)

	_user_email = Global.email
	_loading_label.text = " "

	if Global.pending_verify_token != "":
		_verify_token(Global.pending_verify_token)
		Global.pending_verify_token = ""
	elif Global._ev_message != "":
		_apply_state(Global._ev_state, Global._ev_message, Global._ev_success)
	else:
		_apply_state("waiting", "Please check your email for a verification link.", true)


func _apply_state(state: String, message: String, success: bool) -> void:
	_continue_btn.hide()
	_resend_btn.hide()

	match state:
		"verified":
			_title.text = "Email Verified"
			_message.text = message if message != "" else "Your email has been verified successfully!"
			_message.add_theme_color_override("font_color", TEXT_SUCCESS)
			_continue_btn.show()
			_continue_btn.text = "Continue to Login"

		"expired":
			_title.text = "Link Expired"
			_message.text = message if message != "" else "This verification link has expired. Please request a new one."
			_message.add_theme_color_override("font_color", TEXT_WARNING)
			_resend_btn.show()
			_resend_btn.text = "Resend Verification Email"
			_continue_btn.show()
			_continue_btn.text = "Go to Login"

		"invalid":
			_title.text = "Invalid Link"
			_message.text = message if message != "" else "This verification link is invalid."
			_message.add_theme_color_override("font_color", TEXT_FAIL)
			_continue_btn.show()
			_continue_btn.text = "Go to Login"

		"already_verified":
			_title.text = "Already Verified"
			_message.text = message if message != "" else "Your email is already verified. You can log in."
			_message.add_theme_color_override("font_color", TEXT_SUCCESS)
			_continue_btn.show()
			_continue_btn.text = "Continue to Login"

		_:  # "waiting" or default
			_title.text = "Check Your Email"
			_message.text = message if message != "" else "Please check your email for a verification link."
			_message.add_theme_color_override("font_color", TEXT_SUCCESS if success else TEXT_FAIL)
			_resend_btn.show()
			_resend_btn.text = "Resend Verification Email"
			_continue_btn.show()
			_continue_btn.text = "Go to Login"

	WoodPanel.play_entrance(_panel)


func _verify_token(token: String) -> void:
	_continue_btn.hide()
	_resend_btn.hide()
	_loading_label.text = "Verifying..."
	_title.text = "Email Verification"

	var res: Dictionary = await APIClient.verify_email(token)
	_loading_label.text = " "

	if not bool(res.get("ok", false)):
		var body: Variant = res.get("body")
		if typeof(body) == TYPE_DICTIONARY:
			var err := str(body.get("error", ""))
			match err:
				"TOKEN_EXPIRED":
					_apply_state("expired", "", false)
					return
				"ALREADY_VERIFIED":
					_apply_state("already_verified", "", true)
					return
				_:
					_apply_state("invalid", "", false)
					return
		_apply_state("invalid", "", false)
		return

	_apply_state("verified", "", true)


func _on_continue() -> void:
	SceneManager.goto_login()


func _on_resend() -> void:
	var e := _user_email
	if e == "":
		SceneManager.goto_login()
		return

	_resend_btn.disabled = true
	_resend_btn.text = "Sending..."
	_loading_label.text = " "

	var res: Dictionary = await APIClient.resend_verification(e)

	_resend_btn.disabled = false
	_resend_btn.text = "Resend Verification Email"
	_loading_label.text = "Verification email requested. If it does not arrive, ask the server owner to check email delivery."
	if not res.get("ok", false):
		_loading_label.text = APIClient.error_text(res)
