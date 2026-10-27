extends SceneTree
## Real account flows against verify_integration.py's disposable local backend.
var failures := 0
var session: Node
var api: Node
var state: Node
var manager: Node
var output := ""
func _initialize() -> void: call_deferred("run")
func check(value: bool,message: String) -> void:
	print("AUTH_CHECK ",message," ","PASS" if value else "FAIL")
	if not value: failures+=1
func wait_for(predicate: Callable,seconds: float=15) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		if predicate.call(): return true
		await create_timer(0.05).timeout
	return false
func show_scene(path: String) -> Node:
	if current_scene!=null: current_scene.queue_free(); await process_frame
	var scene: Node=load(path).instantiate(); root.add_child(scene); current_scene=scene
	await create_timer(0.3).timeout; return scene
func routed() -> void:
	await wait_for(func(): return not manager._is_transitioning)
	await process_frame
func mail_token(address: String,kind: String) -> String:
	var response: Dictionary=await api._request_json(HTTPClient.METHOD_GET,"/integration/mail/"+address.uri_encode()+"/"+kind,null,{})
	check(response.get("ok",false),"local fixture captured "+kind)
	return str(api.data_of(response).get("token",""))
func run() -> void:
	session=root.get_node("Global"); api=root.get_node("APIClient"); state=root.get_node("GameState"); manager=root.get_node("SceneManager")
	output=OS.get_environment("WANDERVILLE_TEST_SYNC")
	if OS.get_environment("WANDERVILLE_TEST_RESTART")=="1":
		var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.path_join("onboarding-restart.json")))
		var title: Node=await show_scene("res://Scenes/menus/TitleScreen.tscn")
		check(title.continue_button.visible,"restart restores Continue")
		await title._continue_journey(); await routed()
		check(current_scene.scene_file_path==manager.WORLD_SCENE,"returning account reaches World directly")
		check(session.selected_character==expected.character and session.selected_world_id==expected.world,"restart preserves preset and owned world")
		check(int(state.profile.get("tutorial_step",0))>=1,"welcome acknowledgement persists on server")
		check(state.house.id==1,"restart restores this account's scoped local house")
		await finish("AUTH_RESTART_RESULT"); return
	session.clear_session()
	var startup: Node=await show_scene(manager.TITLE_SCENE)
	var password := OS.get_environment("WANDERVILLE_TEST_PASSWORD")
	var address := "new_wanderer@example.com"
	var signup: Node=await show_scene("res://Scenes/menus/SignupScene.tscn")
	signup.get_node("%UsernameInput").text="new_wanderer"
	signup.get_node("%DisplayNameInput").text="New Wanderer"
	signup.get_node("%EmailInput").text=address
	signup.get_node("%PasswordInput").text=password
	signup.get_node("%ConfirmInput").text=password
	await signup._on_create()
	check(signup.get_node("%SuccessPanel").visible,"signup card creates an account and shows matching verification state")
	session.pending_verify_token=await mail_token(address,"email_verification")
	var verify: Node=await show_scene("res://Scenes/menus/EmailVerificationScene.tscn")
	check(await wait_for(func(): return verify.get_node("%Title").text=="Email Verified"),"verification link completes in the shared card")
	var login: Node=await show_scene("res://Scenes/menus/LoginScene.tscn")
	login.get_node("%UsernameInput").text=address; login.get_node("%PasswordInput").text="Incorrect-password1!"
	await login._on_login()
	check(not login.get_node("%ErrorLabel").text.strip_edges().is_empty() and not login.get_node("%LoginBtn").disabled,"invalid password has retryable inline feedback")
	login.get_node("%PasswordInput").text=password
	await login._on_login(); await routed()
	check(current_scene.scene_file_path==manager.CHARACTER_SELECT_SCENE,"new account goes from authentication to character selection")
	if current_scene.scene_file_path!=manager.CHARACTER_SELECT_SCENE: await finish("AUTH_RESULT"); return
	var editor: Node=current_scene.editor
	editor._choose("boy_b"); await editor.save(); await routed()
	check(current_scene.scene_file_path==manager.WORLD_SCENE,"single-map setup skips map choice and showcase")
	check(session.selected_character=="boy_b" and not session.selected_world_id.is_empty(),"preset and actual owned-world ID are saved")
	check(await wait_for(func(): return int(state.profile.get("tutorial_step",0))>=1),"non-blocking welcome advances existing server tutorial state")
	var response: Dictionary=await api.get_profile()
	check(api.data_of(response).get("character_code")=="boy_b" and api.data_of(response).get("map_code")=="campus","setup is persisted to the backend")
	var owned: String=session.selected_world_id
	var forgot: Node=await show_scene("res://Scenes/menus/ForgotPasswordScene.tscn")
	forgot.get_node("%EmailInput").text=address; await forgot._on_send()
	check(forgot.get_node("%SuccessPanel").visible,"recovery requests reset through the shared card")
	session.pending_reset_token=await mail_token(address,"password_reset")
	var reset: Node=await show_scene("res://Scenes/menus/ResetPasswordScene.tscn")
	var replacement := password+"R"
	reset.get_node("%PasswordInput").text=replacement; reset.get_node("%ConfirmInput").text=replacement
	await reset._on_reset(); check(reset.get_node("%SuccessPanel").visible,"reset link accepts matching new password")
	login=await show_scene("res://Scenes/menus/LoginScene.tscn")
	login.get_node("%UsernameInput").text="new_wanderer"; login.get_node("%PasswordInput").text=replacement
	await login._on_login(); await routed()
	check(current_scene.scene_file_path==manager.WORLD_SCENE and session.selected_world_id==owned,"returning login retains setup and skips selection")
	manager.goto_character_customization(true); await routed()
	var host: Node=current_scene.get_node("CustomizationInteractions")
	host._activate(&"mirror"); host._creator._choose("girl_c"); await host._creator.save()
	response=await api.get_profile(); check(api.data_of(response).get("character_code")=="boy_b","Mirror does not write to the account")
	host.close(); host._activate(&"character"); host._creator._choose("girl_c"); host.close()
	response=await api.get_profile(); check(api.data_of(response).get("character_code")=="boy_b","Wardrobe Cancel does not write a draft")
	host._activate(&"character"); host._creator._choose("girl_b"); await host._creator.save()
	response=await api.get_profile()
	check(api.data_of(response).get("character_code")=="girl_b" and session.selected_world_id==owned,"Wardrobe Save changes preset without clearing the world")
	host.close(); manager.leave_character_customization(); await routed()
	check(current_scene.scene_file_path==manager.WORLD_SCENE,"Wardrobe returns to the existing world")
	state.load_house()
	state.house={"id":1,"position":Vector2(2700,800),"stage":"outer","floor":"","furniture":[]}
	state.save_house()
	var token: String=session.token
	var hud: Node=current_scene.get_node("WorldHUD")
	await hud.switch_panel("settings")
	var settings: Node=hud.get_node("%Settings")
	check(settings._leave_button.visible,"authenticated Settings offers Leave World")
	await settings._on_leave_world(); await routed()
	check(current_scene.scene_file_path==manager.TITLE_SCENE and session.token==token,"Leave World keeps login and returns to title")
	check(current_scene.find_child("OpeningSplash",true,false)==null and current_scene.continue_button.visible,"Leave World preserves Continue directly on the menu")
	await current_scene._continue_journey(); await routed()
	check(current_scene.scene_file_path==manager.WORLD_SCENE and state.house.id==1,"Continue after leaving restores this account's house")
	var file := FileAccess.open(output.path_join("onboarding-restart.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"character":session.selected_character,"world":session.selected_world_id})); file.close()
	await finish("AUTH_RESULT")

func finish(label: String) -> void:
	if current_scene!=null: current_scene.queue_free(); current_scene=null
	api.realtime.clear_session()
	await create_timer(4.2).timeout
	print(label," failures=",failures); quit(failures)
