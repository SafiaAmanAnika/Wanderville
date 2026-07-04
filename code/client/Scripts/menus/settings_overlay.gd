extends Control

@onready var _music_slider: HSlider = %MusicSlider
@onready var _sfx_slider: HSlider = %SFXSlider
@onready var _remember_check: CheckBox = %RememberCheck
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	visible = false
	_music_slider.value = AudioManager.music_volume
	_sfx_slider.value = AudioManager.sfx_volume
	_remember_check.button_pressed = Global.remember_device

	_music_slider.value_changed.connect(_on_music_changed)
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	_remember_check.toggled.connect(_on_remember_toggled)
	_close_button.pressed.connect(_on_close)


func _on_music_changed(value: float) -> void:
	AudioManager.set_music_volume(value)


func _on_sfx_changed(value: float) -> void:
	AudioManager.set_sfx_volume(value)


func _on_remember_toggled(toggled: bool) -> void:
	Global.remember_device = toggled
	Global.save_session()


func _on_close() -> void:
	visible = false
