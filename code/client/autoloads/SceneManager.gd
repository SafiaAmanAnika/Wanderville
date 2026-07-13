extends Node

const LOGIN_SCENE := "res://Scenes/menus/LoginScene.tscn"
const SIGNUP_SCENE := "res://Scenes/menus/SignupScene.tscn"
const MAIN_MENU_SCENE := "res://Scenes/menus/MainMenu.tscn"

const TITLE_SCENE := "res://Scenes/menus/TitleScreen.tscn"
const MAP_SELECTION_SCENE := "res://Scenes/menus/MapSelectionScreen.tscn"
const MAP_SHOWCASE_SCENE := "res://Scenes/menus/MapShowcaseScreen.tscn"
const CHARACTER_SELECT_SCENE := "res://Scenes/menus/CharacterSelectScreen.tscn"
const WORLD_SCENE := "res://Scenes/world.tscn"

const FORGOT_PASSWORD_SCENE := "res://Scenes/menus/ForgotPasswordScene.tscn"
const EMAIL_VERIFICATION_SCENE := "res://Scenes/menus/EmailVerificationScene.tscn"
const RESET_PASSWORD_SCENE := "res://Scenes/menus/ResetPasswordScene.tscn"

const PIXEL_FONT := preload("res://Assets/fonts/BoldPixels.ttf")

var _transition_layer: CanvasLayer
var _overlay: ColorRect
var _bar: ProgressBar
var _status_label: Label
var _is_transitioning: bool = false


func _ready() -> void:
	_build_transition_ui()


func _build_transition_ui() -> void:
	_transition_layer = CanvasLayer.new()
	_transition_layer.layer = 100
	add_child(_transition_layer)

	_overlay = ColorRect.new()
	_overlay.color = Color(0.05, 0.03, 0.01, 0.0)
	_overlay.anchors_preset = Control.PRESET_FULL_RECT
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_transition_layer.add_child(_overlay)

	var center := CenterContainer.new()
	center.anchors_preset = Control.PRESET_FULL_RECT
	_transition_layer.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	center.add_child(vbox)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_override("font", PIXEL_FONT)
	_status_label.add_theme_font_size_override("font_size", WoodPanel.SIZE_BUTTON)
	_status_label.add_theme_color_override("font_color", Color(0.95, 0.91, 0.80))
	vbox.add_child(_status_label)

	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(280, 14)
	_bar.max_value = 100.0
	_bar.value = 0.0
	_bar.show_percentage = false

	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color = Color(0.22, 0.15, 0.08)
	bg_sb.set_corner_radius_all(4)
	bg_sb.set_border_width_all(2)
	bg_sb.border_color = Color(0.38, 0.25, 0.13)
	_bar.add_theme_stylebox_override("background", bg_sb)

	var fill_sb := StyleBoxFlat.new()
	fill_sb.bg_color = Color(0.60, 0.78, 0.35)
	fill_sb.set_corner_radius_all(3)
	_bar.add_theme_stylebox_override("fill", fill_sb)

	vbox.add_child(_bar)

	_transition_layer.visible = false


func transition_to(scene_path: String, status: String = "Loading...") -> void:
	if _is_transitioning:
		return
	_is_transitioning = true

	_transition_layer.visible = true
	_status_label.text = status
	_bar.value = 0.0
	_overlay.color.a = 0.0

	var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_overlay, "color:a", 0.85, 0.3)
	tw.parallel().tween_property(_bar, "value", 40.0, 0.3)
	await tw.finished

	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame

	_bar.value = 80.0
	var tw2 := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw2.tween_property(_bar, "value", 100.0, 0.25)
	await tw2.finished

	var tw3 := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw3.tween_property(_overlay, "color:a", 0.0, 0.3)
	await tw3.finished

	_transition_layer.visible = false
	_is_transitioning = false


func goto_login() -> void:
	transition_to(LOGIN_SCENE, "Loading...")


func goto_signup() -> void:
	transition_to(SIGNUP_SCENE, "Loading...")


func goto_main_menu() -> void:
	transition_to(MAIN_MENU_SCENE, "Loading...")


func goto_title() -> void:
	transition_to(TITLE_SCENE, "Loading...")


func goto_map_selection() -> void:
	transition_to(MAP_SELECTION_SCENE, "Entering world...")


func goto_map_showcase() -> void:
	transition_to(MAP_SHOWCASE_SCENE, "Loading worlds...")


func goto_character_select() -> void:
	transition_to(CHARACTER_SELECT_SCENE, "Loading characters...")


func goto_world() -> void:
	transition_to(WORLD_SCENE, "Entering world...")


func goto_forgot_password() -> void:
	transition_to(FORGOT_PASSWORD_SCENE, "Loading...")


func goto_email_verification(message: String = "", success: bool = true) -> void:
	Global._ev_message = message
	Global._ev_success = success
	transition_to(EMAIL_VERIFICATION_SCENE, "Loading...")


func goto_reset_password(token: String = "") -> void:
	Global.pending_reset_token = token
	transition_to(RESET_PASSWORD_SCENE, "Loading...")


func goto_post_login() -> void:
	if Global.has_completed_setup():
		goto_world()
	else:
		goto_map_selection()
