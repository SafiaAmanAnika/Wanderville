extends Control

const PIXEL_FONT := preload("res://Assets/fonts/BoldPixels.ttf")
const BG_TEXTURE := preload("res://Assets/background/bg.png")

const TEXT_SUCCESS := Color(0.50, 0.78, 0.45)
const TEXT_FAIL := Color(0.90, 0.38, 0.30)

@onready var _bg: TextureRect = %Background
@onready var _title: Label = %Title
@onready var _message: Label = %MessageLabel
@onready var _continue_btn: WoodButton = %ContinueBtn


func _ready() -> void:
	_bg.texture = BG_TEXTURE

	WoodPanel.apply_title_style(_title)

	_message.add_theme_font_override("font", PIXEL_FONT)
	_message.add_theme_font_size_override("font_size", 10)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_continue_btn.pressed.connect(_on_continue)

	var msg_text: String = Global._ev_message
	var success: bool = Global._ev_success
	if msg_text == "":
		msg_text = "Please check your email for a verification link."

	_message.text = msg_text
	if success:
		_message.add_theme_color_override("font_color", TEXT_SUCCESS)
		_title.text = "Email Verification"
	else:
		_message.add_theme_color_override("font_color", TEXT_FAIL)
		_title.text = "Verification Failed"

	_play_entrance()


func _play_entrance() -> void:
	var panel: PanelContainer = %FormPanel
	panel.modulate.a = 0.0
	var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(panel, "modulate:a", 1.0, 0.4)


func _on_continue() -> void:
	SceneManager.goto_login()
