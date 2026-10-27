extends CanvasLayer
## Non-blocking, account-scoped welcome and a few prompts near real interactions.
const Style := preload("res://Scripts/ui/lobby_theme.gd")
const PREFS := "user://onboarding.cfg"
var welcome: PanelContainer
var tip: PanelContainer
var tip_text: Label
var _tip_message := ""
var _prefs := ConfigFile.new()
var _account := ""
var _session := -1
var _spawn := Vector2.ZERO
var _store := Rect2()
var _remaining := 0.0
var _active := ""
var _player: Node2D

func _ready() -> void:
	layer=15; _session=Global.session_version
	_account=APIClient.base_url.sha256_text()+"_"+str(Global.player_id)
	_prefs.load(PREFS)
	_player=get_parent().get_node_or_null("girl")
	if _player==null: return
	_spawn=_player.global_position
	var footprint := get_parent().find_child("Collision_cds",true,false) as CollisionPolygon2D
	if footprint!=null and not footprint.polygon.is_empty():
		_store=Rect2(footprint.to_global(footprint.polygon[0]),Vector2.ZERO)
		for point in footprint.polygon: _store=_store.expand(footprint.to_global(point))
	tip=_card(); tip_text=_label("",20); tip_text.autowrap_mode=TextServer.AUTOWRAP_OFF
	tip.add_child(tip_text); tip.hide()
	get_viewport().size_changed.connect(_fit)
	if not GameState.read_only and int(GameState.profile.get("tutorial_step",0))==0 and not _seen("welcome"):
		_show_welcome()
	_fit()

func _card() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel",UiSkin.panel())
	UiSkin.ink_text(panel)
	add_child(panel); return panel

func _label(text: String,font_size: int) -> Label:
	var label := Style.label(text,font_size)
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color",UiSkin.INK)
	return label

func _show_welcome() -> void:
	welcome=_card(); welcome.name="FirstEntryWelcome"
	var column := VBoxContainer.new(); column.mouse_filter=Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation",10); welcome.add_child(column)
	column.add_child(_label("Welcome to Wanderville",34))
	column.add_child(_label("A new beginning, a world of possibilities.",23))
	column.add_child(_label("Move with WASD · Press E to interact",20))
	var fade := create_tween(); fade.tween_interval(2.8)
	fade.tween_property(welcome,"modulate:a",0.0,0.7)
	fade.tween_callback(func(): welcome.hide())
	_remember("welcome")
	_advance_welcome()

func _advance_welcome() -> void:
	if not Global.is_logged_in(): return
	var response: Dictionary=await APIClient.authenticated(HTTPClient.METHOD_POST,"/profile/tutorial",{"expected_step":0})
	if _session==Global.session_version and response.get("ok",false):
		GameState.profile["tutorial_step"]=int(APIClient.data_of(response).get("step",1))

func _seen(key: String) -> bool:
	return bool(_prefs.get_value(_account,key,false))

func _remember(key: String) -> void:
	_prefs.set_value(_account,key,true); _prefs.save(PREFS)

func context_at(point: Vector2) -> Dictionary:
	if not _seen("movement") and point.distance_to(_spawn)<160:
		return {"key":"movement","text":"Near spawn · Move with WASD. Walk up to an interaction and follow its prompt."}
	var farm := get_parent().get_node_or_null("FarmController")
	if farm!=null and not GameState.read_only:
		var area := Rect2(farm.FARM_AREA_MIN,farm.FARM_AREA_MAX-farm.FARM_AREA_MIN)
		if area.grow(250).has_point(point): return {"key":"planting","text":"Near the farm · Click a nearby grass tile to till, then click the soil to choose a seed."}
	if _store.has_area() and _store.grow(250).has_point(point):
		return {"key":"store","text":"CDS · Click the building, then a shelf to browse your items, buy or sell."}
	return {}

func _process(delta: float) -> void:
	if _session!=Global.session_version: queue_free(); return
	if not is_instance_valid(_player) or tip==null: return
	if _player.global_position.distance_to(_spawn)>40:
		_remember_once("movement")
		if _active=="movement": _remaining=0.0
	_remaining=maxf(0,_remaining-delta)
	var blocked := GameState.menu_open or GameState.social_open
	if blocked and welcome!=null: welcome.hide()
	var house_prompt := get_node_or_null("/root/HousePrompt")
	if house_prompt!=null and house_prompt._panel.visible: blocked=true
	if blocked or (welcome!=null and welcome.visible): tip.hide(); return
	if _remaining>0: tip.show(); return
	tip.hide(); _active=""
	var context := context_at(_player.global_position)
	if not context.is_empty() and not _seen(context.key):
		_active=context.key; _tip_message=context.text; _remaining=5.0
		_remember(_active); tip.show(); _fit()

func _remember_once(key: String) -> void:
	if not _seen(key): _remember(key)

func _fit() -> void:
	var viewport := get_viewport().get_visible_rect().size
	if welcome!=null:
		var factor := minf(1.0,(viewport.x-48)/820.0)
		welcome.custom_minimum_size=Vector2(820,0); welcome.reset_size()
		welcome.scale=Vector2.ONE*factor
		welcome.position=Vector2((viewport.x-welcome.size.x*factor)/2,viewport.y*0.18)
	if tip!=null:
		var width := minf(760,viewport.x-48)
		var style := tip.get_theme_stylebox("panel")
		var room := width-style.content_margin_left-style.content_margin_right
		tip_text.text=_wrap_tip(_tip_message,room)
		tip.custom_minimum_size=Vector2(width,0)
		tip.reset_size(); tip.position=Vector2((viewport.x-tip.size.x)/2,viewport.y-tip.size.y-92)


func _wrap_tip(message: String, width: float) -> String:
	var font := tip_text.get_theme_font("font")
	var font_size := tip_text.get_theme_font_size("font_size")
	var lines := PackedStringArray()
	var line := ""
	for word in message.split(" ",false):
		var candidate := word if line.is_empty() else line+" "+word
		if not line.is_empty() and font.get_string_size(candidate,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>width:
			lines.append(line)
			line=word
		else:
			line=candidate
	lines.append(line)
	return "\n".join(lines)
