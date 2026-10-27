extends SceneTree
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool,message: String) -> void:
	print("PET_AUTH_CHECK ",message," PASS" if value else " FAIL")
	if not value: failures+=1
func wait_for(predicate: Callable) -> bool:
	var end := Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<end:
		if predicate.call(): return true
		await create_timer(0.05).timeout
	return false
func run() -> void:
	var account: Dictionary=JSON.parse_string(OS.get_environment("TEST_PET_ACCOUNT"))
	var session := root.get_node("Global"); var state := root.get_node("GameState")
	var api := root.get_node("APIClient"); var manager := root.get_node("SceneManager")
	session.clear_session(); session.set_session(account.token,{"id":account.player_id,"username":account.username})
	var response: Dictionary=await api.update_profile({"character_code":"girl_a","map_code":"campus"})
	check(response.get("ok",false) and await state.load_from_backend(),"real account initializes its pet")
	manager.goto_world()
	check(await wait_for(func(): return current_scene!=null and current_scene.scene_file_path==manager.WORLD_SCENE and not manager._is_transitioning),"normal world route completes")
	var pets: Node=current_scene.get_node("Pets")
	check(await wait_for(func(): return pets._loaded),"companion loads from the authenticated pet API")
	var button: Button=current_scene.get_node("WorldHUD/Screen/QuickActions/PetButton")
	button.pressed.emit()
	check(pets.panel.visible and state.menu_open,"HUD paw opens the actual pet selector")
	await pets.choose("fox")
	check(pets.companion.species=="fox","choosing a pet updates the active sprite")
	response=await api.authenticated(HTTPClient.METHOD_GET,"/pets")
	check(api.data_of(response).get("species")=="fox","selection is committed to the signed-in account")
	pets.close_menu(); manager.goto_world()
	check(await wait_for(func(): return not manager._is_transitioning),"world reload completes")
	pets=current_scene.get_node("Pets")
	check(await wait_for(func(): return pets._loaded),"saved pet loads after world reload")
	check(pets.companion.species=="fox","world reload preserves the chosen companion")
	print("PET_AUTH_RESULT failures=",failures)
	quit(1 if failures else 0)
