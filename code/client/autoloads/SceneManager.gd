extends Node

const LOGIN_SCENE := "res://Scenes/menus/LoginScene.tscn"
const SIGNUP_SCENE := "res://Scenes/menus/SignupScene.tscn"
const MAIN_MENU_SCENE := "res://Scenes/menus/MainMenu.tscn"

const TITLE_SCENE := "res://Scenes/menus/TitleScreen.tscn"
const MAP_SELECTION_SCENE := "res://Scenes/menus/MapSelectionScreen.tscn"
const MAP_SHOWCASE_SCENE := "res://Scenes/menus/MapShowcaseScreen.tscn"
const CHARACTER_SELECT_SCENE := "res://Scenes/menus/CharacterSelectScreen.tscn"
const WORLD_SCENE := "res://Scenes/world.tscn"
const PROFILE_SCENE := "res://Scenes/menus/ProfileScene.tscn"
const SOCIAL_LOBBY_SCENE := "res://Scenes/SocialLobby.tscn"
const CHARACTER_CUSTOMIZATION_SCENE := "res://Scenes/CustomizationLobby.tscn"

const FORGOT_PASSWORD_SCENE := "res://Scenes/menus/ForgotPasswordScene.tscn"
const EMAIL_VERIFICATION_SCENE := "res://Scenes/menus/EmailVerificationScene.tscn"
const RESET_PASSWORD_SCENE := "res://Scenes/menus/ResetPasswordScene.tscn"

# One short warm-dark fade is shared by every scene change. There is no status
# text and no progress bar, and the overlay is fully opaque while the next
# scene builds and initialises its camera, so no gray frame can ever show.
const FADE_TIME := 0.15
const FADE_COLOR := Color(0.14, 0.08, 0.03)

var _transition_layer: CanvasLayer
var _overlay: ColorRect
var _is_transitioning: bool = false
var _customization_from_world := false
var _customization_return_position := Vector2.ZERO
var _customization_return_session := -1
var _social_return_position := Vector2.ZERO
var _social_return_session := -1
var _social_from_world := false


func _ready() -> void:
	_build_transition_ui()


func _build_transition_ui() -> void:
	_transition_layer = CanvasLayer.new()
	_transition_layer.layer = 100
	add_child(_transition_layer)

	_overlay = ColorRect.new()
	_overlay.color = Color(FADE_COLOR.r, FADE_COLOR.g, FADE_COLOR.b, 0.0)
	_overlay.anchors_preset = Control.PRESET_FULL_RECT
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_transition_layer.add_child(_overlay)

	_transition_layer.visible = false


func transition_to(scene_path: String) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true

	_transition_layer.visible = true
	_overlay.color.a = 0.0

	var fade_out := create_tween().set_ease(Tween.EASE_IN_OUT)
	fade_out.tween_property(_overlay, "color:a", 1.0, FADE_TIME)
	await fade_out.finished

	get_tree().change_scene_to_file(scene_path)
	# Let the destination build and initialise its camera while it is hidden.
	await get_tree().process_frame
	await get_tree().process_frame

	var fade_in := create_tween().set_ease(Tween.EASE_IN_OUT)
	fade_in.tween_property(_overlay, "color:a", 0.0, FADE_TIME)
	await fade_in.finished

	_transition_layer.visible = false
	_is_transitioning = false


func goto_login() -> void:
	transition_to(LOGIN_SCENE)


func goto_signup() -> void:
	transition_to(SIGNUP_SCENE)


func goto_main_menu() -> void:
	transition_to(MAIN_MENU_SCENE)


func goto_title() -> void:
	transition_to(TITLE_SCENE)


func goto_map_selection() -> void:
	transition_to(MAP_SELECTION_SCENE)


func goto_map_showcase() -> void:
	transition_to(MAP_SHOWCASE_SCENE)


func goto_character_select() -> void:
	transition_to(CHARACTER_SELECT_SCENE)


func goto_profile() -> void:
	transition_to(PROFILE_SCENE)


func goto_world() -> void:
	transition_to(WORLD_SCENE)


func goto_social_lobby() -> void:
	if _is_transitioning: return
	var scene := get_tree().current_scene
	_social_from_world = scene != null and scene.scene_file_path == WORLD_SCENE
	_social_return_session = Global.session_version
	if _social_from_world:
		var player := scene.get_node_or_null("girl") as Node2D
		if player != null: _social_return_position = player.global_position
	transition_to(SOCIAL_LOBBY_SCENE)


func leave_social_lobby() -> void:
	goto_world()


func goto_character_customization(from_world: bool = false) -> void:
	if _is_transitioning: return
	_customization_from_world = from_world
	_customization_return_session = Global.session_version
	if from_world:
		var player := get_tree().current_scene.get_node_or_null("girl") as Node2D
		if player != null: _customization_return_position = player.global_position
	transition_to(CHARACTER_CUSTOMIZATION_SCENE)


func leave_character_customization() -> void:
	if _customization_from_world and _customization_return_session == Global.session_version:
		goto_world()
	else:
		_customization_from_world = false
		goto_character_select()


func restore_customization_return(player: Node2D) -> void:
	if _social_from_world and _social_return_session == Global.session_version:
		player.global_position = _social_return_position
	_social_from_world = false
	if _customization_from_world and _customization_return_session == Global.session_version:
		player.global_position = _customization_return_position
	_customization_from_world = false


func goto_forgot_password() -> void:
	transition_to(FORGOT_PASSWORD_SCENE)


func goto_email_verification(message: String = "", success: bool = true) -> void:
	Global._ev_message = message
	Global._ev_success = success
	transition_to(EMAIL_VERIFICATION_SCENE)


func goto_reset_password(token: String = "") -> void:
	Global.pending_reset_token = token
	transition_to(RESET_PASSWORD_SCENE)


func goto_post_login() -> void:
	if Global.has_completed_setup():
		goto_world()
	else:
		goto_map_selection()
