extends SceneTree
var failures := 0
var output := "res://../../test-output/onboarding"
var session: Node
var state: Node
func _initialize() -> void: call_deferred("run")
func check(value: bool,message: String) -> void:
	print("ONBOARDING_CHECK ",message," ","PASS" if value else "FAIL")
	if not value: failures+=1
func settle(seconds: float=0.08) -> void: await create_timer(seconds).timeout
func shot(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await settle()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name+".png"))
func show_scene(path: String) -> Node:
	if current_scene!=null: current_scene.queue_free(); await process_frame
	var scene: Node=load(path).instantiate(); root.add_child(scene); current_scene=scene
	await settle(0.4); return scene

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size=Vector2i(1920,1088)
	session=root.get_node("Global"); state=root.get_node("GameState")
	root.get_node("APIClient").base_url="http://127.0.0.1:1/onboarding-visual"
	session.clear_session(); state.menu_open=false; state.social_open=false
	var title: Node=await show_scene("res://Scenes/menus/TitleScreen.tscn")
	var backdrop: Node=root.get_node("SceneManager").journey_backdrop
	var player: Node=backdrop.player
	title.begin_button.pressed.emit(); await settle(0.6)
	var login := current_scene
	check(login.scene_file_path.ends_with("LoginScene.tscn"),"Begin goes directly to the login card")
	check(root.get_node("SceneManager").journey_backdrop==backdrop and backdrop.player==player and is_zero_approx(backdrop.dim.color.a),"Title and auth reuse the same background without a dark effect")
	var login_frame: Texture2D=login.get_node("%FormPanel").get_theme_stylebox("panel").texture
	check(login_frame.resource_path.ends_with("parchment-frame.res") and login.find_child("AuthLogo",true,false)!=null,"Login uses the painted ivy frame and supplied logo")
	var password: LineEdit=login.get_node("%PasswordInput")
	var eye: Button=password.get_parent().get_node("PasswordEye")
	check(password.get_global_rect().encloses(eye.get_global_rect()),"Password eye sits inside the field")
	for field in login.find_children("*","LineEdit",true,false):
		check(field.get_node_or_null("FieldIcon")!=null,"Account fields contain their reference icons")
	check(password.secret,"Password starts hidden")
	eye.button_pressed=true; check(not password.secret,"Eye reveals password"); eye.button_pressed=false
	login._on_login(); await settle()
	check(not login.get_node("%ErrorLabel").text.strip_edges().is_empty(),"Empty login reports an inline error")
	login.get_node("%ErrorLabel").text=" "
	await shot("login")
	login.find_child("CreateAccountLink",true,false).pressed.emit(); await settle(0.6)
	var signup := current_scene
	check(signup.scene_file_path.ends_with("SignupScene.tscn"),"Create Account opens signup")
	check(signup.get_node("%FormPanel").get_theme_stylebox("panel").texture==login_frame,"Signup and login share the card design")
	check(signup.find_children("PasswordEye","Button",true,false).size()==2,"Signup has password and confirmation visibility controls")
	var google: Button=signup.get_node("%GoogleBtn")
	check(google.find_child("GoogleLogo",true,false).texture.resource_path.ends_with("google-g.png") and google.get_theme_stylebox("normal").bg_color==Color.WHITE,"Google uses official multicolored icon on white")
	signup.get_node("%PasswordInput").text="Abcdef12!"; signup._on_password_changed("")
	check(signup.get_node("%PasswordStrength").text=="Very Strong","Password strength feedback is connected")
	signup.get_node("%UsernameInput").text="fixture"; signup.get_node("%EmailInput").text="fixture@example.com"
	signup.get_node("%ConfirmInput").text="Different12!"; signup._on_create(); await settle()
	check(signup.get_node("%ErrorLabel").text.contains("match"),"Mismatched confirmation is rejected without submitting")
	signup.get_node("%ErrorLabel").text=" "; signup.get_node("%UsernameInput").text=""; signup.get_node("%EmailInput").text=""
	signup.get_node("%PasswordInput").text=""; signup.get_node("%ConfirmInput").text=""; signup._on_password_changed("")
	await shot("signup")
	root.size=Vector2i(960,640); await settle()
	var panel: Control=signup.get_node("%FormPanel")
	check(Rect2(Vector2.ZERO,root.get_visible_rect().size).encloses(panel.get_global_transform()*Rect2(Vector2.ZERO,panel.size)),"Signup fits a compact window")
	await shot("signup-compact"); root.size=Vector2i(1920,1088)
	var forgot: Node=await show_scene("res://Scenes/menus/ForgotPasswordScene.tscn")
	await shot("recovery")
	forgot.get_node("%EmailInput").text="fixture@example.com"; await forgot._on_send(); await settle()
	check(forgot.get_node("%FormPanel").visible and not forgot.get_node("%SuccessPanel").visible,"Offline recovery shows retry instead of claiming email was sent")
	session.pending_reset_token="visual-token"
	var reset: Node=await show_scene("res://Scenes/menus/ResetPasswordScene.tscn")
	await shot("reset-password")
	var verification: Node=await show_scene("res://Scenes/menus/EmailVerificationScene.tscn")
	verification._apply_state("verified","Your email is verified. You're ready to begin.",true); await settle(0.3)
	await shot("verified")
	session.selected_character=""; session.selected_world_id=""
	var select: Node=await show_scene("res://Scenes/menus/CharacterSelectScreen.tscn")
	var editor: Node=select.editor
	check(editor.mode=="first_time" and editor.options.get_child_count()==6 and editor.options.columns==3,"Onboarding uses six presets in the shared editor")
	for card in editor.options.get_children():
		check(card.find_children("*","AnimatedSprite2D",true,false).is_empty(),"Small portrait is static")
		var picture: TextureRect=card.get_child(0)
		check(Rect2(Vector2.ZERO,card.size).encloses(Rect2(picture.position,picture.size)),"Portrait fits its card")
		check(picture.position.y+picture.size.y<card.get_child(1).position.y,"Portrait leaves its caption readable")
	for code in editor.CODES:
		editor._choose(code)
		check(is_equal_approx(editor.avatar.position.y+97*editor.avatar.scale.y,320),"Preview retains the ground anchor for "+code)
	editor._choose("girl_a"); await shot("character-selection")
	root.size=Vector2i(960,640); await settle()
	check(Rect2(Vector2.ZERO,root.get_visible_rect().size).encloses(editor.get_global_transform()*Rect2(Vector2.ZERO,editor.size)),"Character editor fits a compact window")
	await shot("character-compact"); root.size=Vector2i(1920,1088)
	session.selected_character="boy_c"; session.selected_world_id="retained-world"
	var room: Node=await show_scene("res://Scenes/CustomizationLobby.tscn")
	var host: Node=room.get_node("CustomizationInteractions")
	host._activate(&"mirror"); await settle(); editor=host._creator
	check(editor.mode=="mirror" and not editor.options.visible and not editor._save.visible,"Mirror hides editing and saving")
	editor._choose("girl_a"); await editor.save()
	check(session.selected_character=="boy_c" and editor.draft=="boy_c","Mirror cannot change the account even through programmatic Save")
	await shot("mirror"); host.close()
	host._activate(&"character"); editor._choose("girl_b"); await settle()
	check(session.selected_character=="boy_c","Wardrobe edits a draft")
	await shot("wardrobe"); host.close(); check(session.selected_character=="boy_c","Cancel retains the saved preset")
	session.selected_character="farmer_female"; host._activate(&"mirror"); await settle()
	check(host._creator.avatar.character=="farmer_female","Mirror preserves and previews the legacy equipped character")
	host.close(); session.selected_character="girl_a"
	state.profile={"tutorial_step":0}; state.menu_open=false; state.social_open=false
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://onboarding.cfg"))
	var world: Node=await show_scene("res://Scenes/world.tscn")
	root.get_node("HousePrompt").hide_text()
	var guide: Node
	for child in world.get_children():
		if child.get_script()==load("res://Scripts/ui/onboarding_guide.gd"): guide=child
	check(guide!=null and guide.welcome.visible and not state.menu_open,"First entry welcomes without blocking movement")
	check(guide.context_at(guide._spawn).get("key")=="movement","Spawn guidance appears only before learning movement")
	var wasd := InputEventKey.new(); wasd.physical_keycode=KEY_W
	check(InputMap.action_has_event("ui_up",wasd),"Welcome instructions match actual WASD bindings")
	var body: CharacterBody2D=world.get_node("girl"); var before:=body.position
	Input.action_press("ui_right"); for i in 8: await physics_frame
	Input.action_release("ui_right"); check(body.position.distance_to(before)>10,"Movement works during welcome")
	await shot("first-entry")
	var farm: Node=world.get_node("FarmController")
	var farm_center: Vector2=(farm.FARM_AREA_MIN+farm.FARM_AREA_MAX)/2
	check(guide.context_at(farm_center).get("key")=="planting","Farm guidance uses the existing farming area")
	check(guide.context_at(guide._store.get_center()).get("key")=="store","Store guidance points to actual CDS")
	await settle(4.1); check(not guide.welcome.visible,"Welcome fades automatically")
	world=await show_scene("res://Scenes/world.tscn")
	for child in world.get_children():
		if child.get_script()==load("res://Scripts/ui/onboarding_guide.gd"): guide=child
	check(guide.welcome==null,"The same account does not replay the welcome")
	current_scene.queue_free(); current_scene=null; await settle(4.2)
	print("ONBOARDING_RESULT failures=",failures); quit(failures)
