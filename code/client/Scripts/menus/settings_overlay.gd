extends Control

signal closed

const PIXEL_FONT := preload("res://Assets/fonts/BoldPixels.ttf")
const BG_TEXTURE := preload("res://Assets/background/bg.webp")

@onready var _title: Label = %Title
@onready var _music_slider: HSlider = %MusicSlider
@onready var _sfx_slider: HSlider = %SFXSlider
@onready var _music_label: Label = $Center/Panel/VBox/MusicRow/MusicLabel
@onready var _sfx_label: Label = $Center/Panel/VBox/SFXRow/SFXLabel
@onready var _remember_check: CheckBox = %RememberCheck
@onready var _close_button: Button = %CloseButton
@onready var _panel: PanelContainer = $Center/Panel

var _tween: Tween
var _saving := false
var _logout_dialog: Control
var _music_mute: CheckBox
var _leave_button: Button


func _ready() -> void:
	visible = false
	_apply_styles()
	_apply_panel_style()
	_music_slider.value = AudioManager.music_volume
	_sfx_slider.value = AudioManager.sfx_volume
	_music_mute = CheckBox.new()
	_music_mute.text = "Mute"
	_music_mute.button_pressed = AudioManager.music_muted
	_music_slider.get_parent().add_child(_music_mute)
	_check_font(_music_mute, WoodPanel.SIZE_FIELD)
	_music_mute.add_theme_color_override("font_color", preload("res://Scripts/ui/lobby_theme.gd").INK)
	_music_mute.add_theme_color_override("font_hover_color", preload("res://Scripts/ui/lobby_theme.gd").INK)
	_music_mute.toggled.connect(AudioManager.set_music_muted)
	_remember_check.button_pressed = Global.remember_device

	_music_slider.value_changed.connect(_on_music_changed)
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	_remember_check.toggled.connect(_on_remember_toggled)
	_close_button.pressed.connect(_on_close)
	WoodPanel.apply_status_label(%SaveStatus)
	%LogoutButton.visible = Global.is_logged_in()
	%ProfileButton.visible = Global.is_logged_in()
	%ProfileButton.pressed.connect(_on_profile)
	_logout_dialog = preload("res://Scenes/menus/LogoutConfirmationDialog.tscn").instantiate()
	add_child(_logout_dialog)
	%LogoutButton.pressed.connect(func() -> void: _logout_dialog.show_dialog())
	_leave_button = preload("res://Scripts/ui/lobby_theme.gd").button("Leave World")
	_leave_button.name = "LeaveWorldButton"
	%CloseButton.get_parent().add_child(_leave_button)
	%CloseButton.get_parent().move_child(_leave_button, %LogoutButton.get_index())
	_leave_button.hide()
	_leave_button.pressed.connect(_on_leave_world)


func _apply_panel_style() -> void:
	preload("res://Scripts/ui/lobby_theme.gd").apply_tree(_panel)
	_panel.add_theme_stylebox_override("panel", UiSkin.panel())
	UiSkin.ink_text(_panel)


func _apply_styles() -> void:
	WoodPanel.apply_panel_title_style(_title)

	_label_font(_music_label, WoodPanel.SIZE_FIELD)
	_label_font(_sfx_label, WoodPanel.SIZE_FIELD)
	_check_font(_remember_check, WoodPanel.SIZE_FIELD)

	_style_slider(_music_slider)
	_style_slider(_sfx_slider)


func _label_font(label: Label, size: int) -> void:
	label.add_theme_font_override("font", preload("res://Scripts/ui/lobby_theme.gd").body_font())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", WoodPanel.TEXT_COLOR)


func _style_slider(slider: HSlider) -> void:
	var track := UiSkin.progress_track()
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area_highlight", UiSkin.progress_fill())

	var grabber_area := UiSkin.progress_fill()
	slider.add_theme_stylebox_override("grabber_area", grabber_area)

	slider.add_theme_icon_override("grabber", _make_grabber_icon())
	slider.add_theme_icon_override("grabber_highlight", _make_grabber_icon())
	slider.add_theme_constant_override("slider_height", 12)


func _make_grabber_icon() -> Texture2D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var gold := Color(0.85, 0.72, 0.38)
	var dark := Color(0.45, 0.30, 0.15)
	for x in range(16):
		for y in range(16):
			var cx := x - 7.5
			var cy := y - 7.5
			if cx * cx + cy * cy <= 49.0:
				img.set_pixel(x, y, gold)
			elif cx * cx + cy * cy <= 64.0:
				img.set_pixel(x, y, dark)
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


func _check_font(check: CheckBox, size: int) -> void:
	check.add_theme_font_override("font", preload("res://Scripts/ui/lobby_theme.gd").body_font())
	check.add_theme_font_size_override("font_size", size)
	check.add_theme_color_override("font_color", WoodPanel.TEXT_COLOR)


func show_overlay() -> void:
	var scene := get_tree().current_scene
	_leave_button.visible = scene != null and scene.scene_file_path in [SceneManager.WORLD_SCENE, SceneManager.SOCIAL_LOBBY_SCENE, SceneManager.CHARACTER_CUSTOMIZATION_SCENE, SceneManager.MARKETPLACE_SCENE]
	_music_slider.set_value_no_signal(AudioManager.music_volume)
	_music_mute.set_pressed_no_signal(AudioManager.music_muted)
	%LogoutButton.visible = Global.is_logged_in()
	%ProfileButton.visible = Global.is_logged_in()
	%SaveStatus.text = ""
	visible = true
	modulate.a = 0.0
	_panel.scale = Vector2(0.92, 0.92)
	_panel.pivot_offset = _panel.size / 2.0
	_kill_tween()
	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "modulate:a", 1.0, 0.3)
	_tween.parallel().tween_property(_panel, "scale", Vector2.ONE, 0.35)


func _on_music_changed(value: float) -> void:
	AudioManager.set_music_volume(value)


func _on_sfx_changed(value: float) -> void:
	AudioManager.set_sfx_volume(value)


func _on_remember_toggled(toggled: bool) -> void:
	Global.remember_device = toggled
	Global.save_session()


func _on_close() -> void:
	await request_close()


func _on_profile() -> void:
	if await request_close():
		SceneManager.goto_profile()


func _on_leave_world() -> void:
	if _saving or _logout_dialog.visible: return
	_leave_button.disabled = true
	if await request_close():
		var response: Dictionary = await SceneManager.leave_world()
		if not response.get("ok",false):
			show_overlay()
			%SaveStatus.text = APIClient.error_text(response)
	_leave_button.disabled = false


func request_close() -> bool:
	if _saving or _logout_dialog.visible:
		return false
	_saving = true
	if Global.is_logged_in():
		_close_button.disabled = true
		var response: Dictionary = await APIClient.update_profile({"music_volume": roundi(AudioManager.music_volume), "effects_volume": roundi(AudioManager.sfx_volume)})
		_close_button.disabled = false
		if not bool(response.get("ok", false)):
			%SaveStatus.text = APIClient.error_text(response)
			GameState.report_error(response)
			_saving = false
			return false
	_saving = false
	_kill_tween()
	visible = false
	closed.emit()
	return true


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
