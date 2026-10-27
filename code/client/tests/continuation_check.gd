extends SceneTree
## Isolated profiles only: launch/transition rendering, account house saves, Leave.
var failures := 0
var output := "res://../../test-output/continuation"
func _initialize() -> void: call_deferred("run")
func check(value: bool,message: String) -> void:
	print("CONTINUATION_CHECK ",message," ","PASS" if value else "FAIL")
	if not value: failures+=1
func settle(seconds: float=0.1) -> void: await create_timer(seconds).timeout
func shot(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name+".png"))
func routed() -> void:
	var manager := root.get_node("SceneManager")
	var deadline := Time.get_ticks_msec()+30000
	while manager._is_transitioning and Time.get_ticks_msec()<deadline: await settle(0.05)
	check(not manager._is_transitioning,"Scene transition completes")
func set_account(id: int,world: int) -> void:
	var session := root.get_node("Global"); var state := root.get_node("GameState")
	session.set_session("isolated-account",{"id":id,"username":"fixture_"+str(id)})
	session.selected_character="girl_a"; session.selected_world_id=str(world)
	state.owned_world={"id":world}
	state.apply_session({"session_mode":"OWNER","owned_world_id":world,"current_world_id":world})
	state.load_house()
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size=Vector2i(1578,997)
	var api := root.get_node("APIClient"); api.base_url="http://127.0.0.1:1/continuation"
	var session := root.get_node("Global"); var state := root.get_node("GameState"); var manager := root.get_node("SceneManager")
	session.clear_session()
	# Re-runs keep this isolated profile; remove only the named fixture saves.
	for key in [[7001,101],[7001,103],[7002,102]]:
		set_account(key[0],key[1]); DirAccess.remove_absolute(ProjectSettings.globalize_path(state.house_save_path()))
	session.clear_session()
	# Old opening preferences must not bring back the removed seed screen.
	var prefs := ConfigFile.new(); prefs.set_value("opening","seen",true); prefs.save("user://title_preferences.cfg")
	var title: Node=load(manager.TITLE_SCENE).instantiate(); root.add_child(title); current_scene=title
	await settle(); check(title.find_child("OpeningSplash",true,false)==null and title.begin_button.has_focus(),"Startup reaches the title directly despite old opening preferences")
	await shot("startup")
	manager.show_loading(); await settle(); await shot("loading")
	check(manager._loading_screen.message.text=="Purring...","Scene loading displays Purring")
	var intro_background: TextureRect=manager.journey_backdrop.village
	var loading_background: TextureRect=manager._loading_screen.background
	check(loading_background.texture==intro_background.texture and loading_background.stretch_mode==intro_background.stretch_mode and loading_background.get_global_rect().is_equal_approx(intro_background.get_global_rect()),"Loading matches the title background's aspect ratio, scale and crop")
	root.size=Vector2i(960,640); await settle()
	check(loading_background.get_global_rect().is_equal_approx(intro_background.get_global_rect()),"Background framing stays identical in a compact window")
	root.size=Vector2i(1920,1088); await settle()
	check(loading_background.get_global_rect().is_equal_approx(intro_background.get_global_rect()),"Background framing stays identical in a widescreen window")
	root.size=Vector2i(1578,997); await settle()
	check(manager._loading_screen.visible and manager._transition_layer.visible,"Loading cover is visible before work starts")
	check(manager._loading_screen.bar.progress<0,"Unknown-duration loading uses a moving indicator without an invented percentage")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://Assets/ui/loading_boot.png")
	manager._loading_screen.set_progress(0.62); await settle()
	check(is_equal_approx(manager._loading_screen.bar.progress,0.62),"Loading bar accepts measured resource progress")
	await shot("loading-progress")
	manager.hide_loading()
	manager.goto_login(); await settle(0.01)
	check(manager._loading_screen.visible,"Navigation uses the themed loading cover")
	await routed(); var login:=current_scene; await settle(0.3)
	check(loading_background.get_global_rect().is_equal_approx(manager.journey_backdrop.village.get_global_rect()),"Sign-in and loading preserve the same background framing")
	var google: Button=login.get_node("%GoogleBtn")
	var icon: Control=google.find_child("GoogleLogo",true,false)
	var label: Control=google.find_child("GoogleLabel",true,false)
	check(icon.get_global_rect().end.x<label.get_global_rect().position.x and not google.get_theme_font("font") is SystemFont,"Google icon and label have separate bounds and bundled typography")
	var content_bounds := icon.get_global_rect().merge(label.get_global_rect())
	check(absf(content_bounds.get_center().x-google.get_global_rect().get_center().x)<2,"Google icon and label are centered as one group")
	await shot("login")
	var loading_label: Label=login.get_node("%LoadingLabel")
	var inline_bar: Control=loading_label.get_parent().get_node("SharedLoadingProgress")
	loading_label.text="Logging in..."; await settle()
	check(inline_bar.visible and not loading_label.visible,"Authentication loading uses the same inline cat bar")
	check(inline_bar.message.text=="Purring...","Inline loading displays Purring")
	await shot("login-progress")
	loading_label.text="Email sent."; await settle()
	check(not inline_bar.visible and loading_label.visible,"Loading bar preserves success and error text")
	loading_label.text=" "; await settle()
	manager.goto_title(); await routed()
	check(current_scene.find_child("OpeningSplash",true,false)==null,"Returning to title has no seed-opening screen")
	current_scene.queue_free(); current_scene=null; await settle()
	title=load(manager.TITLE_SCENE).instantiate(); root.add_child(title); current_scene=title
	check(title.find_child("OpeningSplash",true,false)==null and title.begin_button.has_focus(),"A fresh launch goes directly to the menu")
	current_scene.queue_free(); current_scene=null; await settle()
	var legacy := FileAccess.open(state.HOUSE_SAVE,FileAccess.WRITE)
	legacy.store_string('{"id":6,"position":[90,70],"stage":"outer","floor":"","furniture":[]}'); legacy.close()
	set_account(7001,101); check(state.house.stage=="none","Signed-in account never inherits ambiguous old house.json")
	state.house={"id":1,"position":Vector2(300,400),"stage":"outer","floor":"","furniture":[{"name":"fixture","x":1,"y":2}]}
	state.save_house(); var alice_path: String=state.house_save_path()
	set_account(7002,102); check(state.house.stage=="none" and state.house.furniture.is_empty(),"Second account begins without first account's house or furniture")
	state.house={"id":2,"position":Vector2(500,600),"stage":"walls","floor":"","furniture":[]}; state.save_house()
	check(alice_path!=state.house_save_path(),"Housing files differ by account/world")
	set_account(7001,101); check(state.house.id==1 and state.house.position==Vector2(300,400) and state.house.furniture.size()==1,"First account restores its own house and furniture")
	state.owned_world={"id":103}; state.apply_session({"session_mode":"OWNER","owned_world_id":103,"current_world_id":103}); state.load_house()
	check(state.house.stage=="none","Another world cannot inherit the same account's different-world house")
	state.apply_session({"session_mode":"OWNER","owned_world_id":101,"current_world_id":101}); state.load_house()
	var original := FileAccess.get_file_as_string(alice_path)
	state._set_read_only(true); state.load_house(); state.house.id=6; state.save_house()
	check(FileAccess.get_file_as_string(alice_path)==original and not state.spend_wood(1),"Visits cannot overwrite housing or spend building wood")
	state._set_read_only(false); state.load_house()
	session.clear_session(); check(state.house.stage=="none" and state.house.furniture.is_empty(),"Logout clears in-memory housing")
	# Actual world checks: periodic sessions don't rebuild a placement; visits do.
	set_account(7001,101); state.house=state.empty_house(); state.save_house()
	var world: Node=load(manager.WORLD_SCENE).instantiate(); root.add_child(world); current_scene=world
	await settle(0.5)
	var housing: Node=world.get_node("HouseManager")
	housing._start_placement(1); var ghost: Node=housing._ghost
	state.session_updated.emit(state.visit_session)
	check(housing._ghost==ghost,"Normal session polling does not reset active house placement")
	state._set_read_only(true); await settle()
	check(housing._ghost==null and not housing._can_edit(),"Visit context cancels local housing placement")
	housing._start_placement(2); housing._sell_house()
	check(housing._ghost==null and state.house.stage=="none","Housing actions are blocked during a visit")
	state._set_read_only(false)
	# Offline button route avoids profile HTTP; authenticated behavior is integrated separately.
	session.token=""; session.player_id=0; state.load_house()
	var hud: Node=world.get_node("WorldHUD")
	await hud.switch_panel("settings"); await settle(0.4)
	var settings: Node=hud.get_node("%Settings")
	check(settings._leave_button.visible,"Settings exposes Leave World")
	await shot("leave-world")
	await settings._on_leave_world(); await routed()
	check(current_scene.scene_file_path==manager.TITLE_SCENE and current_scene.find_child("OpeningSplash",true,false)==null,"Leave World returns directly to the title menu")
	await shot("returned-title")
	current_scene.queue_free(); current_scene=null; await settle(4.2)
	print("CONTINUATION_RESULT failures=",failures); quit(failures)
