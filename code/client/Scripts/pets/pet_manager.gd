extends Node2D
## One active companion per player. Account selection is saved by the pet API.
const Companion := preload("res://Scripts/pets/pet_companion.gd")
const Navigation := preload("res://Scripts/pets/pet_navigation.gd")
const Style := preload("res://Scripts/ui/lobby_theme.gd")
const NAMES := {"cat":"Cat","dog":"Dog","rabbit":"Rabbit","fox":"Fox","duck":"Duck","red_panda":"Red Panda"}
var companion: CharacterBody2D
var navigation: Node
var panel: PanelContainer
var screen: Control
var status: Label
var buttons: Dictionary = {}
var _saving := false
var _version := -1
var _loaded := false
var _notice_until := 0

func _ready() -> void:
	y_sort_enabled=true
	_version=Global.session_version
	navigation=Navigation.new(); navigation.name="PetNavigation"; add_child(navigation)
	_build_menu()
	_start.call_deferred()

func _start() -> void:
	while not navigation.ready_for_paths:
		await get_tree().process_frame
		if not is_inside_tree(): return
	var player := get_parent().get_node_or_null("girl") as CharacterBody2D
	if player==null: return
	var position := Vector2.INF
	for i in range(16):
		var candidate: Vector2=navigation.nearest(player.global_position+Vector2(145,0).rotated(i*TAU/16))
		if candidate.is_finite() and candidate.distance_to(player.global_position)>85:
			position=candidate; break
	if not position.is_finite():
		status.text="Your companion needs a clear place to join you."; return
	companion=Companion.new(); companion.name="Companion"
	companion.owner_body=player; companion.navigation=navigation
	add_child(companion); companion.global_position=position; companion.home=position
	var code := "cat"
	if Global.is_logged_in():
		var response: Dictionary=await APIClient.authenticated(HTTPClient.METHOD_GET,"/pets")
		if not is_inside_tree() or _version!=Global.session_version: return
		if response.get("ok",false): code=str(APIClient.data_of(response).get("species","cat"))
		else: _notice(APIClient.error_text(response))
	else:
		var config := ConfigFile.new()
		if config.load("user://pet_companion.cfg")==OK: code=str(config.get_value("offline","species","cat"))
	companion.set_species(code); _loaded=true; _refresh_buttons()

func _build_menu() -> void:
	var layer := CanvasLayer.new(); layer.layer=25; add_child(layer)
	screen=Control.new(); screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter=Control.MOUSE_FILTER_IGNORE; layer.add_child(screen)
	panel=PanelContainer.new(); panel.theme=Style.theme(); screen.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left=-390; panel.offset_top=-245; panel.offset_right=390; panel.offset_bottom=245
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation",14); panel.add_child(column)
	var row := HBoxContainer.new(); column.add_child(row)
	var title := Style.label("Your companion",30); title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(title)
	var close := Style.button("Close"); row.add_child(close); close.pressed.connect(close_menu)
	var hint := Style.label("Choose a pet to explore with you. They follow, wander and nap.",18)
	hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; column.add_child(hint)
	var grid := GridContainer.new(); grid.columns=3; grid.size_flags_vertical=Control.SIZE_EXPAND_FILL; column.add_child(grid)
	for code in Companion.CODES:
		var button := Style.button(NAMES[code]); button.custom_minimum_size=Vector2(240,130)
		button.toggle_mode=true; button.icon=Companion.frames_for(code).get_frame_texture("walk_s",0)
		button.expand_icon=true; button.add_theme_constant_override("icon_max_width",76)
		button.pressed.connect(choose.bind(code)); grid.add_child(button); buttons[code]=button
	status=Style.label("Your companion is getting ready...",18); status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; column.add_child(status)
	panel.hide()

func open_menu() -> void:
	if GameState.menu_open or GameState.social_open: return
	GameState.menu_open=true; panel.show(); _refresh_buttons()
	buttons.cat.grab_focus()

func close_menu() -> void:
	if not panel.visible: return
	panel.hide(); GameState.menu_open=false

func choose(code: String) -> void:
	if _saving or not is_instance_valid(companion) or code not in Companion.CODES: return
	_notice_until=0; _saving=true; status.text="Saving your companion..."; _refresh_buttons()
	if Global.is_logged_in():
		var response: Dictionary=await APIClient.authenticated(HTTPClient.METHOD_PUT,"/pets",{"species":code})
		if not is_inside_tree() or _version!=Global.session_version: return
		if not response.get("ok",false):
			_saving=false; _notice(APIClient.error_text(response)); _refresh_buttons(); return
	else:
		var config := ConfigFile.new(); config.set_value("offline","species",code)
		if config.save("user://pet_companion.cfg")!=OK:
			_saving=false; _notice("Your companion could not be saved. Try again."); _refresh_buttons(); return
	companion.set_species(code); _saving=false; _refresh_buttons()
	status.text=NAMES[code]+" is your active companion."

func _refresh_buttons() -> void:
	for code in buttons:
		buttons[code].disabled=_saving or not _loaded
		buttons[code].set_pressed_no_signal(is_instance_valid(companion) and companion.species==code)

func _input(event: InputEvent) -> void:
	if panel.visible and event.is_action_pressed("ui_cancel"):
		close_menu(); get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if _version!=Global.session_version:
		close_menu(); queue_free(); return
	if not panel.visible or _saving or not is_instance_valid(companion): return
	if Time.get_ticks_msec()<_notice_until: return
	status.text="%s · %s" % [NAMES[companion.species], ["Relaxing","Following you","Exploring","Sleeping"][companion.state]]

func _notice(message: String) -> void:
	status.text=message; _notice_until=Time.get_ticks_msec()+5000

func _exit_tree() -> void:
	if panel!=null and panel.visible: GameState.menu_open=false
