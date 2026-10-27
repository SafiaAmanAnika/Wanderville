extends Control
## Presentation only; Continue uses the existing authenticated save-loading flow.
@export var background_video: VideoStream
@export var trailer_video: VideoStream

const Style := preload("res://Scripts/ui/lobby_theme.gd")
const SoundToggle := preload("res://Scripts/ui/sound_toggle.gd")
const Card := preload("res://Scripts/ui/title_card.gd")
const LOGO := preload("res://Assets/ui/title/logo.res")
const DESIGN := Vector2(1920, 1088)

var canvas: Control
var menu: VBoxContainer
var continue_button: Button
var begin_button: Button
var music_button: Button
var status: Label
var settings: Control
var popup: Control
var background_player: VideoStreamPlayer
var trailer_player: VideoStreamPlayer
var _busy := false
var _session := -1
var _selected_card: Button
var _selection_cat: TextureRect
var _cat_tween: Tween


func _ready() -> void:
	if Global.pending_verify_token != "":
		SceneManager.goto_email_verification()
		return
	if Global.pending_reset_token != "":
		SceneManager.goto_reset_password(Global.pending_reset_token)
		return
	# A remembered account makes Continue available; it never bypasses the menu.
	if not Global.is_logged_in(): Global.load_session()
	_build_background()
	_build_title()
	_build_settings()
	get_viewport().size_changed.connect(_fit)
	Global.session_changed.connect(_refresh_continue)
	_fit()
	_refresh_continue()
	_focus_menu()


func _full(control: Control, parent: Node) -> void:
	parent.add_child(control)
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _build_background() -> void:
	var backdrop := SceneManager.show_journey_background(self,0.0,background_video)
	background_player = backdrop.player


func _label(text: String, font_size: int, color: Color = Style.PAPER) -> Label:
	var label := Style.label(text, font_size)
	label.add_theme_font_override("font",Style.FONT if font_size >= 28 else Style.body_font())
	label.add_theme_color_override("font_color", color)
	return label


func _build_title() -> void:
	canvas = Control.new(); canvas.name = "TitleComposition"
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas); canvas.size = DESIGN
	var logo := TextureRect.new(); logo.texture = LOGO; logo.name = "Wordmark"
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.position = Vector2(430,125); logo.size = Vector2(1060,340)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE; canvas.add_child(logo)
	menu = VBoxContainer.new(); menu.name = "JourneyMenu"
	menu.position = Vector2(710,510); menu.custom_minimum_size.x = 500
	menu.add_theme_constant_override("separation", -12); canvas.add_child(menu)
	continue_button = _menu_button("Continue Journey", "")
	continue_button.name = "ContinueJourney"; menu.add_child(continue_button)
	continue_button.pressed.connect(_continue_journey)
	begin_button = _menu_button("Begin Adventure", "")
	begin_button.name = "BeginAdventure"; menu.add_child(begin_button)
	begin_button.pressed.connect(_begin_adventure)
	var trailer := _menu_button("Watch Trailer", "play"); trailer.name = "WatchTrailer"; menu.add_child(trailer)
	trailer.tooltip_text = "Trailer coming soon" if trailer_video == null else "Watch the Wanderville trailer"
	trailer.pressed.connect(_watch_trailer)
	var settings_button := _menu_button("Settings","settings"); settings_button.name = "SettingsButton"
	menu.add_child(settings_button); settings_button.pressed.connect(_open_settings)
	_selection_cat = TextureRect.new(); _selection_cat.name = "SelectionCat"
	_selection_cat.texture = preload("res://Assets/ui/title/selection-cat.res")
	_selection_cat.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_selection_cat.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_selection_cat.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_selection_cat.size = Vector2(100,76); _selection_cat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selection_cat.hide(); canvas.add_child(_selection_cat)
	for card in menu.get_children():
		card.focus_entered.connect(_select_card.bind(card))
	status = _label("", 20); status.name = "TitleStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.position = Vector2(650,1000); status.size = Vector2(620,60)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_color_override("font_shadow_color",Color("30241e"))
	status.add_theme_constant_override("shadow_offset_y",2); status.hide(); canvas.add_child(status)
	var footer := HBoxContainer.new(); footer.name = "Footer"
	footer.position = Vector2(70, 994); footer.add_theme_constant_override("separation", 16); canvas.add_child(footer)
	var credits := _quiet_button("Credits"); footer.add_child(credits); credits.pressed.connect(_credits)
	if not OS.has_feature("web") and not OS.has_feature("mobile"):
		var exit_button := _quiet_button("Exit"); footer.add_child(exit_button)
		exit_button.pressed.connect(_on_exit)
	music_button = SoundToggle.new(); music_button.name = "MusicToggle"
	music_button.theme=Style.theme()
	for state in ["normal","hover","pressed","focus"]:
		var sound_backing := StyleBoxTexture.new(); sound_backing.texture = Card.CREAM
		# Use the painted frame itself, excluding the card's transparent padding.
		# The square control can then fill its complete visible and clickable area.
		sound_backing.region_rect = Rect2(37,77,2099,515)
		sound_backing.modulate_color = Color("a46d46")
		music_button.add_theme_stylebox_override(state,sound_backing)
	music_button.position = Vector2(1762, 978); music_button.size = Vector2(86,86)
	canvas.add_child(music_button); music_button.pressed.connect(_toggle_music); _update_music()
	var account := Card.new(); account.configure("Log In / Sign Up","",true,22)
	account.name = "AccountButton"; account.custom_minimum_size = Vector2(300,90)
	account.position = Vector2(1540,34); account.size = Vector2(300,90)
	canvas.add_child(account); account.pressed.connect(_open_account)


func _menu_button(text: String, icon: String) -> Button:
	var button := Card.new(); button.configure(text,icon)
	return button


func _quiet_button(text: String) -> Button:
	var button := Style.button(text); button.custom_minimum_size.y = 48
	button.add_theme_font_size_override("font_size", 23)
	var normal := Style.box(Color("241f1880"), 10); normal.set_border_width_all(0)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_color_override("font_color", Style.PAPER)
	return button


func _build_settings() -> void:
	settings = preload("res://Scenes/menus/SettingsOverlay.tscn").instantiate()
	settings.name = "SharedSettings"; add_child(settings)
	settings.closed.connect(func(): _update_music(); _focus_menu())


func _fit() -> void:
	if canvas == null: return
	var viewport := get_viewport_rect().size
	var factor := minf(viewport.x / DESIGN.x, viewport.y / DESIGN.y)
	canvas.scale = Vector2.ONE * factor; canvas.position = (viewport - DESIGN * factor) / 2.0
	if settings != null:
		var center := settings.get_node("Center") as CenterContainer
		center.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		var settings_factor := minf(1.0, minf(viewport.x / 560.0, viewport.y / 620.0))
		center.scale = Vector2.ONE * settings_factor; center.size = viewport / settings_factor


func _refresh_continue() -> void:
	if continue_button != null:
		continue_button.visible = Global.is_logged_in() and Global.has_completed_setup()
		if _selected_card == null or not _selected_card.visible:
			_select_card(continue_button if continue_button.visible else begin_button, false)
		var cards: Array[Button] = []
		for card in menu.get_children():
			if card.visible: cards.append(card)
		for index in cards.size():
			cards[index].focus_neighbor_top = cards[posmod(index-1,cards.size())].get_path()
			cards[index].focus_neighbor_bottom = cards[(index+1)%cards.size()].get_path()
		_move_selection_cat.call_deferred(false)

func _select_card(card: Button, animate: bool = true) -> void:
	if not is_instance_valid(card) or not card.visible: return
	_selected_card = card
	for button in menu.get_children(): button.set_active(button == card, animate)
	_move_selection_cat.call_deferred(animate)

func _move_selection_cat(animate: bool) -> void:
	if not is_inside_tree() or _selected_card == null or not is_instance_valid(_selection_cat): return
	var target := menu.position + _selected_card.position + Vector2(_selected_card.size.x-116,-38)
	if _cat_tween != null: _cat_tween.kill()
	if animate and _selection_cat.visible:
		_cat_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_cat_tween.tween_property(_selection_cat,"position",target,0.2)
	else: _selection_cat.position = target
	_selection_cat.show()

func _open_account() -> void:
	if _busy or settings.visible or is_instance_valid(popup): return
	SceneManager.goto_login()


func _on_exit() -> void:
	# quit_game() plays the exit sound and waits for it before closing the
	# window; get_tree().quit() would cut it off straight away.
	AudioManager.quit_game()


func _focus_menu() -> void:
	if continue_button.visible: continue_button.grab_focus()
	else: begin_button.grab_focus()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if is_instance_valid(popup):
			_close_popup(); get_viewport().set_input_as_handled()
		elif settings != null and settings.visible:
			settings.request_close(); get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		if _busy or settings.visible or is_instance_valid(popup): return
		var cards: Array[Button] = []
		for card in menu.get_children():
			if card.visible and not card.disabled: cards.append(card)
		var index := cards.find(_selected_card)
		index = clampi(index + (1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1),0,cards.size()-1)
		cards[index].grab_focus(); _select_card(cards[index]); get_viewport().set_input_as_handled()


func _open_settings() -> void:
	if _busy or is_instance_valid(popup): return
	settings.show_overlay(); settings.get_node("%CloseButton").grab_focus()


func _toggle_music() -> void:
	AudioManager.set_music_muted(not AudioManager.music_muted); _update_music()


func _update_music() -> void:
	music_button.muted = AudioManager.music_muted


func _begin_adventure() -> void:
	if _busy or settings.visible or is_instance_valid(popup): return
	if Global.is_logged_in() and not Global.has_completed_setup():
		SceneManager.goto_post_login()
		return
	SceneManager.goto_login()


func _continue_journey() -> void:
	if _busy or settings.visible or is_instance_valid(popup) or not Global.is_logged_in(): return
	_busy = true; _session = Global.session_version
	continue_button.disabled = true; begin_button.disabled = true
	status.text = "Purring..."; status.show()
	SceneManager.show_loading()
	await get_tree().process_frame
	var response: Dictionary = await APIClient.me(Global.token)
	if not is_inside_tree() or _session != Global.session_version:
		_end_loading(); return
	if not bool(response.get("ok", false)):
		_end_loading()
		if int(response.get("status_code", 0)) == 401:
			Global.clear_session(); SceneManager.goto_login()
		else: status.text = "Could not reach your world. Check your connection and try again."
		return
	if not await GameState.load_from_backend():
		_end_loading(); status.text = "Your save could not be loaded. Please try again."
		return
	if _session == Global.session_version: SceneManager.goto_post_login()
	else: _end_loading()


func _end_loading() -> void:
	SceneManager.hide_loading()
	_busy = false; continue_button.disabled = false; begin_button.disabled = false; _refresh_continue()


func _open_popup(title: String) -> VBoxContainer:
	_close_popup()
	popup = Control.new(); popup.name = "TitleDialog"; _full(popup, self)
	var shade := ColorRect.new(); shade.color = Color("16140fce"); _full(shade, popup)
	var center := CenterContainer.new(); _full(center, popup)
	var panel := PanelContainer.new(); panel.theme = Style.theme()
	panel.add_theme_stylebox_override("panel", UiSkin.panel()); center.add_child(panel)
	UiSkin.ink_text(panel)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation", 18); panel.add_child(column)
	var header := HBoxContainer.new(); column.add_child(header)
	var heading := _label(title, 30, Style.INK); heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL; header.add_child(heading)
	var close := Style.button("X"); header.add_child(close); close.pressed.connect(_close_popup)
	return column


func _close_popup() -> void:
	if is_instance_valid(trailer_player): trailer_player.stop()
	if is_instance_valid(popup): popup.queue_free()
	popup = null; trailer_player = null
	if background_video != null and background_player.paused: background_player.paused = false
	if begin_button != null: _focus_menu()


func _credits() -> void:
	if _busy or settings.visible or is_instance_valid(popup): return
	var column := _open_popup("Wanderville")
	column.add_child(_label("Made with Godot Engine.\nFeaturing Wanderville's world\nand character artwork.", 24, Style.INK))


func _watch_trailer() -> void:
	if _busy or settings.visible or is_instance_valid(popup): return
	if trailer_video == null:
		var message := _open_popup("Watch Trailer")
		message.add_child(_label("The trailer is coming soon.",24,Style.INK))
		return
	var column := _open_popup("Wanderville trailer"); background_player.paused = true
	trailer_player = VideoStreamPlayer.new(); trailer_player.stream = trailer_video
	trailer_player.expand = true; trailer_player.custom_minimum_size = Vector2(720, 405)
	column.add_child(trailer_player); trailer_player.play(); trailer_player.finished.connect(_close_popup)
