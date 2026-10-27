extends PanelContainer
## One six-preset editor, with first-time, Wardrobe and read-only Mirror modes.
const Style := preload("res://Scripts/ui/lobby_theme.gd")
const Preview := preload("res://Scripts/customization/character_preview.gd")
const Frames := preload("res://Scripts/chara_frames.gd")
const CODES := ["girl_a","girl_b","girl_c","boy_a","boy_b","boy_c"]
signal close_requested
signal saved(code: String)
var avatar: Preview
var title_label: Label
var status: Label
var options: GridContainer
var draft := "girl_a"
var mode := "wardrobe"
var _session := -1
var _saving := false
var _save: Button
var _cancel: Button
var _heading: Label
var _step: Label
var _name: Label
var _help: Label
var _direction_label: Label
var _pause: Button
var _action: OptionButton
var _body: HBoxContainer
var _right: VBoxContainer

func _ready() -> void:
	theme=Style.theme(); custom_minimum_size=Vector2(1100,720)
	add_theme_stylebox_override("panel",UiSkin.panel())
	UiSkin.ink_text(self)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation",18); add_child(column)
	var header := HBoxContainer.new(); column.add_child(header)
	_heading=Style.label("Choose Your Character",30); _heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL; header.add_child(_heading)
	_step=Style.label("Getting Started",18); header.add_child(_step)
	var body := HBoxContainer.new(); body.size_flags_vertical=Control.SIZE_EXPAND_FILL
	_body=body
	body.add_theme_constant_override("separation",20); column.add_child(body)
	var stage_panel := PanelContainer.new(); stage_panel.add_theme_stylebox_override("panel",Style.box(Color("d6d3b4"),0)); body.add_child(stage_panel)
	var stage := Control.new(); stage.custom_minimum_size=Vector2(380,500); stage_panel.add_child(stage)
	var live := Style.label("Live Character Preview",20); live.position=Vector2(30,20); live.size.x=320
	live.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; stage.add_child(live)
	var guide := Line2D.new(); guide.default_color=Color("aaa98a"); guide.width=2
	guide.points=PackedVector2Array([Vector2(70,320),Vector2(310,320)]); stage.add_child(guide)
	avatar=Preview.new(); stage.add_child(avatar)
	_name=Style.label("Girl A",22); _name.position=Vector2(20,344); _name.size.x=340
	_name.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; stage.add_child(_name)
	_preview_controls(stage)
	var right := VBoxContainer.new(); right.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_right=right
	right.add_theme_constant_override("separation",16); body.add_child(right)
	title_label=Style.label("Choose one of six characters",24); right.add_child(title_label)
	options=GridContainer.new(); options.name="CharacterGrid"; options.columns=3
	options.add_theme_constant_override("h_separation",10); options.add_theme_constant_override("v_separation",10); right.add_child(options)
	_help=Style.label("You can change your character later in the Wardrobe.",19)
	_help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; right.add_child(_help)
	var footer := HBoxContainer.new(); footer.add_theme_constant_override("separation",12); column.add_child(footer)
	status=Style.label("",18); status.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; footer.add_child(status)
	preload("res://Scripts/ui/loading_progress.gd").attach(status)
	_cancel=Style.button("Cancel"); footer.add_child(_cancel); _cancel.pressed.connect(func():
		if not _saving: close_requested.emit()
	)
	_save=Style.button("Save Appearance",true); _save.custom_minimum_size=Vector2(210,48)
	UiSkin.apply_buy_sell_button(_save)
	footer.add_child(_save); _save.pressed.connect(save)
	get_viewport().size_changed.connect(_fit); minimum_size_changed.connect(_fit.call_deferred); _fit.call_deferred()

func _fit() -> void:
	size=get_combined_minimum_size().max(custom_minimum_size)
	var viewport := get_viewport_rect().size
	var factor := minf(1.0,minf((viewport.x-40)/size.x,(viewport.y-40)/size.y))
	scale=Vector2.ONE*maxf(0.1,factor); position=(viewport-size*scale)/2.0

func begin(kind: String="character") -> void:
	mode="first_time" if kind=="first_time" else "mirror" if kind=="mirror" else "wardrobe"
	_session=Global.session_version; _saving=false; _save.disabled=false; _cancel.disabled=false
	draft=Global.selected_character if Global.CHARACTERS.has(Global.selected_character) else "girl_a"
	if mode!="mirror" and draft not in CODES: draft="girl_a"
	avatar.set_character(draft); avatar.set_pose("idle","front"); _fit_avatar()
	_action.select(0); _direction_label.text="Front"; _pause.text="Pause"
	var readonly := mode=="mirror"
	custom_minimum_size=Vector2(720 if readonly else 1100,720)
	_right.visible=not readonly
	_body.alignment=BoxContainer.ALIGNMENT_CENTER if readonly else BoxContainer.ALIGNMENT_BEGIN
	_heading.text="Mirror" if readonly else "Choose Your Character" if mode=="first_time" else "The Wardrobe"
	_step.text="Getting Started" if mode=="first_time" else "Current character" if readonly else "Character presets"
	title_label.text="Your equipped character" if readonly else "Choose one of six characters"
	_help.text="Turn and animate your current character. Your saved appearance stays unchanged." if readonly else "You can change your character later in the Wardrobe."
	options.visible=not readonly; _save.visible=not readonly
	_save.text="Choose Character" if mode=="first_time" else "Save Appearance"
	_cancel.text="Close" if readonly else "Back" if mode=="first_time" else "Cancel"
	for child in options.get_children(): options.remove_child(child); child.queue_free()
	if not readonly:
		var group := ButtonGroup.new()
		for code in CODES:
			var button := Style.button(""); button.name=code; button.custom_minimum_size=Vector2(194,166)
			button.toggle_mode=true; button.button_group=group; button.button_pressed=code==draft; options.add_child(button)
			button.clip_contents=true
			button.add_theme_stylebox_override("normal",UiSkin.slot())
			button.add_theme_stylebox_override("hover",UiSkin.slot(UiSkin.HOVER_TINT))
			button.add_theme_stylebox_override("pressed",UiSkin.slot(UiSkin.GOLD_TINT))
			button.add_theme_stylebox_override("hover_pressed",UiSkin.slot(UiSkin.GOLD_TINT))
			var picture := TextureRect.new(); picture.texture=Frames.portrait(Global.CHARACTERS[code].folder)
			picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			picture.position=Vector2(47,10); picture.size=Vector2(100,110)
			picture.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST; picture.mouse_filter=Control.MOUSE_FILTER_IGNORE; button.add_child(picture)
			var label := Style.label(Global.CHARACTERS[code].name,19); label.position=Vector2(8,124); label.size.x=178
			label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; label.mouse_filter=Control.MOUSE_FILTER_IGNORE; button.add_child(label)
			button.pressed.connect(func(): _choose(code))
	status.text="Preview only" if readonly else "Choose a character to begin." if mode=="first_time" else "Your saved appearance."
	_fit()

func _fit_avatar() -> void:
	# Calibrate from front idle once per selection, never from the current frame.
	var idle: SpriteFrames
	if draft in CODES: idle=Frames.preview_frames(Global.CHARACTERS[draft].folder,"idle")
	else: idle=avatar.sprite_frames
	var animation := "idle_front"
	var texture := idle.get_frame_texture(animation,0)
	var rect := texture.get_image().get_used_rect()
	var factor := 220.0/maxf(1,rect.size.y)
	avatar.scale=Vector2.ONE*factor
	var ground := 321.0 if draft in CODES else float(rect.end.y)
	avatar.position=Vector2(190,320-(ground-texture.get_height()/2.0)*factor)
	_name.text=Global.CHARACTERS.get(draft,{"name":"Girl A"}).name

func _choose(code: String) -> void:
	if mode=="mirror" or _saving or code not in CODES: return
	draft=code; avatar.character=code; _set_preview_pose(avatar.action,avatar.direction); _fit_avatar()
	for index in options.get_child_count(): options.get_child(index).set_pressed_no_signal(CODES[index]==draft)
	status.text="Changes not saved" if draft!=Global.selected_character else "Your saved appearance."

func _preview_controls(stage: Control) -> void:
	var controls := VBoxContainer.new(); controls.position=Vector2(16,386); controls.custom_minimum_size=Vector2(348,0); stage.add_child(controls)
	var rotation := HBoxContainer.new(); controls.add_child(rotation)
	var previous := Style.button("<"); rotation.add_child(previous); previous.tooltip_text="Turn counterclockwise"; previous.pressed.connect(func(): _turn_preview(-1))
	_direction_label=Style.label("Front",18); _direction_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_direction_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; rotation.add_child(_direction_label)
	var next := Style.button(">"); rotation.add_child(next); next.tooltip_text="Turn clockwise"; next.pressed.connect(func(): _turn_preview(1))
	var playback := HBoxContainer.new(); controls.add_child(playback)
	_action=OptionButton.new(); _action.name="PreviewAction"; _action.size_flags_horizontal=Control.SIZE_EXPAND_FILL; playback.add_child(_action)
	for action in Frames.ACTIONS: _action.add_item(action.capitalize())
	_action.item_selected.connect(func(index: int): _set_preview_pose(Frames.ACTIONS[index],avatar.direction))
	_pause=Style.button("Pause"); _pause.name="PreviewPlayback"; playback.add_child(_pause)
	_pause.pressed.connect(func():
		if avatar.is_playing(): avatar.pause(); _pause.text="Play"
		else: avatar.play(); _pause.text="Pause"
	)
	var step := Style.button("Step"); step.name="PreviewFrameStep"; playback.add_child(step)
	step.pressed.connect(func():
		avatar.pause(); avatar.set_frame_and_progress((avatar.frame+1)%avatar.sprite_frames.get_frame_count(avatar.animation),0.0); _pause.text="Play"
	)

func _turn_preview(delta: int) -> void:
	var slot: int=Frames.DIRECTIONS.find(avatar.direction)
	_set_preview_pose(avatar.action,Frames.DIRECTIONS[posmod(slot+delta,8)])

func _set_preview_pose(action: String,direction: String) -> void:
	var playing := avatar.is_playing(); var pose := avatar.frame; var progress := avatar.frame_progress
	avatar.set_pose(action,direction,pose)
	avatar.set_frame_and_progress(posmod(pose,avatar.sprite_frames.get_frame_count(avatar.animation)),progress)
	if not playing: avatar.pause()
	_direction_label.text=direction.replace("_"," ").capitalize()

func cancel() -> void:
	pass # A draft never mutates the session or active player.

func save() -> void:
	if mode=="mirror" or _saving or _session!=Global.session_version: return
	_saving=true; _save.disabled=true; _cancel.disabled=true
	status.text="Saving your character..."
	var response := {"ok":true}
	if mode=="first_time":
		response=await SceneManager.save_initial_character(draft)
	elif Global.is_logged_in() and draft!=Global.selected_character:
		response=await APIClient.update_profile({"character_code":draft})
	if _session!=Global.session_version:
		status.text="The signed-in account changed. Close and reopen this screen."; _saving=false; _cancel.disabled=false
		return
	if not response.get("ok",false):
		status.text=APIClient.error_text(response); _saving=false; _save.disabled=false; _cancel.disabled=false
		return
	var changed := Global.selected_character!=draft
	Global.selected_character=draft; Global.modular_look={}
	Global.save_session(); Global.appearance_changed.emit()
	var room := get_tree().current_scene
	if mode!="first_time" and changed and room!=null and room.has_method("respawn_player"): room.respawn_player()
	status.text="Character saved."; _saving=false; _save.disabled=false; _cancel.disabled=false
	saved.emit(draft)
