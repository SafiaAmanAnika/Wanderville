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
const MARKETPLACE_SCENE := "res://Scenes/marketplace.tscn"

const FORGOT_PASSWORD_SCENE := "res://Scenes/menus/ForgotPasswordScene.tscn"
const EMAIL_VERIFICATION_SCENE := "res://Scenes/menus/EmailVerificationScene.tscn"
const RESET_PASSWORD_SCENE := "res://Scenes/menus/ResetPasswordScene.tscn"

# A shared illustrated progress screen covers scene loading and initialization.
const FADE_TIME := 0.15

var _transition_layer: CanvasLayer
var _is_transitioning: bool = false
var _visit_arrival := Vector2.INF
var _visit_arrival_world := 0
var _visit_arrival_session := -1
var _customization_from_world := false
var _customization_return_scene := CHARACTER_SELECT_SCENE
var _customization_return_position := Vector2.ZERO
var _customization_return_session := -1
var _social_return_position := Vector2.ZERO
var _social_return_session := -1
var _social_from_world := false
var journey_backdrop: CanvasLayer
var _loading_screen: Control


func show_journey_background(owner: Node, darkness: float = 0.0, stream: VideoStream = null) -> CanvasLayer:
	if not is_instance_valid(journey_backdrop):
		journey_backdrop = preload("res://Scripts/menus/journey_backdrop.gd").new()
		add_child(journey_backdrop)
	journey_backdrop.present(owner,darkness,stream)
	return journey_backdrop

var _market_return_position := Vector2.ZERO
var _market_return_session := -1
var _market_from_world := false

func _ready() -> void:
	_build_transition_ui()


func _build_transition_ui() -> void:
	_transition_layer = CanvasLayer.new()
	_transition_layer.layer = 100
	add_child(_transition_layer)

	_transition_layer.visible = false
	_loading_screen = preload("res://Scripts/ui/loading_screen.gd").new()
	_transition_layer.add_child(_loading_screen)
	_loading_screen.hide()


func show_loading(message: String = "Purring...") -> void:
	_transition_layer.show()
	_loading_screen.start(message)
	_loading_screen.modulate.a = 1.0
	_loading_screen.show()


func hide_loading() -> void:
	if _is_transitioning: return
	_loading_screen.hide()
	_transition_layer.hide()


func transition_to(scene_path: String) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true

	show_loading()
	# Present a rendered cover before requesting or instantiating the next scene.
	await get_tree().process_frame
	await get_tree().process_frame
	var requested := ResourceLoader.load_threaded_request(scene_path)
	if requested != OK:
		_is_transitioning = false; hide_loading()
		GameState.report_error({"message":"This place could not be loaded. Please try again."})
		return
	var progress: Array = []
	while ResourceLoader.load_threaded_get_status(scene_path,progress) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		if not progress.is_empty(): _loading_screen.set_progress(float(progress[0])*0.9)
		await get_tree().process_frame
	var packed := ResourceLoader.load_threaded_get(scene_path) as PackedScene
	if packed == null:
		_is_transitioning = false; hide_loading()
		GameState.report_error({"message":"This place could not be loaded. Please try again."})
		return
	get_tree().change_scene_to_packed(packed)
	AudioManager.music_for_scene(scene_path)
	_loading_screen.set_progress(0.95)
	await get_tree().process_frame
	await get_tree().process_frame

	var fade_in := create_tween().set_ease(Tween.EASE_IN_OUT)
	_loading_screen.set_progress(1.0)
	fade_in.tween_property(_loading_screen, "modulate:a", 0.0, FADE_TIME)
	await fade_in.finished

	_transition_layer.visible = false
	_loading_screen.hide()
	_is_transitioning = false


func leave_world() -> Dictionary:
	if _is_transitioning: return {"ok":false,"message":"Please wait for the current journey to finish."}
	var version := Global.session_version
	if GameState.is_visiting():
		var response: Dictionary = await APIClient.leave_farm()
		if not response.get("ok",false): return response
		var session: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_GET,"/farm/visiting/session")
		if not session.get("ok",false): return session
		if version!=Global.session_version: return {"ok":false,"stale":true,"message":"The signed-in account changed."}
		GameState.apply_session(APIClient.data_of(session))
	GameState.save_house()
	APIClient.realtime.clear_session()
	GameState.menu_open = false; GameState.social_open = false
	_social_from_world = false; _customization_from_world = false
	transition_to(TITLE_SCENE)
	return {"ok":true}


func goto_login() -> void:
	transition_to(LOGIN_SCENE)


func goto_signup() -> void:
	transition_to(SIGNUP_SCENE)


func goto_main_menu() -> void:
	transition_to(MAIN_MENU_SCENE)


func goto_title() -> void:
	transition_to(TITLE_SCENE)


func goto_map_selection() -> void:
	goto_post_login()


func goto_map_showcase() -> void:
	goto_post_login()


func goto_character_select() -> void:
	transition_to(CHARACTER_SELECT_SCENE)


func goto_profile() -> void:
	transition_to(PROFILE_SCENE)


func goto_world() -> void:
	APIClient.realtime.enter_world(GameState.desired_world_id())
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
	_customization_return_scene = SOCIAL_LOBBY_SCENE if get_tree().current_scene != null and get_tree().current_scene.scene_file_path == SOCIAL_LOBBY_SCENE else CHARACTER_SELECT_SCENE
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
		transition_to(_customization_return_scene if _customization_return_session == Global.session_version else CHARACTER_SELECT_SCENE)


func goto_visited_world(world_id: int, arrival: Vector2) -> void:
	if _is_transitioning or not GameState.is_visiting() or GameState.current_world_id() != world_id: return
	_social_from_world = false
	_customization_from_world = false
	_market_from_world = false
	_visit_arrival = arrival
	_visit_arrival_world = world_id
	_visit_arrival_session = Global.session_version
	goto_world()

func restore_customization_return(player: Node2D) -> void:
	if _visit_arrival.is_finite():
		if _visit_arrival_session == Global.session_version and GameState.is_visiting() and GameState.current_world_id() == _visit_arrival_world:
			player.global_position = _visit_arrival
		_visit_arrival = Vector2.INF
		_social_from_world = false
		_customization_from_world = false
		_market_from_world = false
		return
	if _social_from_world and _social_return_session == Global.session_version:
		player.global_position = _social_return_position
	_social_from_world = false
	if _customization_from_world and _customization_return_session == Global.session_version:
		player.global_position = _customization_return_position
	_customization_from_world = false
	if _market_from_world and _market_return_session == Global.session_version:
		player.global_position = _market_return_position
	_market_from_world = false

func goto_forgot_password() -> void:
	transition_to(FORGOT_PASSWORD_SCENE)


func goto_email_verification(message: String = "", success: bool = true) -> void:
	Global._ev_message = message
	Global._ev_success = success
	transition_to(EMAIL_VERIFICATION_SCENE)


func goto_reset_password(token: String = "") -> void:
	Global.pending_reset_token = token
	transition_to(RESET_PASSWORD_SCENE)

func goto_marketplace() -> void:
	if _is_transitioning: return
	var scene := get_tree().current_scene
	_market_from_world = scene != null and scene.scene_file_path == WORLD_SCENE
	_market_return_session = Global.session_version
	if _market_from_world:
		var player := scene.get_node_or_null("girl") as Node2D
		if player != null: _market_return_position = player.global_position
	transition_to(MARKETPLACE_SCENE)


func leave_marketplace() -> void:
	goto_world()
	
func goto_post_login() -> void:
	if Global.has_completed_setup():
		goto_world()
	else:
		goto_character_select()


func save_initial_character(code: String) -> Dictionary:
	var version := Global.session_version
	if Global.is_logged_in():
		var world: Dictionary = GameState.owned_world
		if not world.has("id"):
			var fetched: Dictionary = await APIClient.get_my_world(Global.token)
			if not fetched.get("ok",false): return fetched
			world = APIClient.data_of(fetched)
		if not world.has("id"): return {"ok":false,"message":"Your world is not available yet. Please try again."}
		var response: Dictionary = await APIClient.update_profile({"character_code":code,"map_code":"campus"})
		if not response.get("ok",false): return response
		if version!=Global.session_version: return {"ok":false,"stale":true}
		Global.selected_world_id=str(world.id)
		GameState.profile=APIClient.data_of(response)
	else:
		Global.selected_world_id="campus"
	return {"ok":true}
