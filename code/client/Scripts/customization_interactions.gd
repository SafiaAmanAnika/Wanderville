extends Node2D
## Original six-character selector and existing profile controls.

const CreatorPanel := preload("res://Scripts/customization/creator_panel.gd")
const LobbyStyle := preload("res://Scripts/ui/lobby_theme.gd")
var _creator: PanelContainer

const WOOD_BUTTON := preload("res://Scripts/components/wood_button.gd")
const LOGOUT_DIALOG := preload("res://Scenes/menus/LogoutConfirmationDialog.tscn")

@onready var player: CharacterBody2D = get_parent().get_node_or_null("LobbyPlayer")
@onready var zones: Node2D = $InteractionZones

var nearest: Area2D
var modal := ""   # "", "character", "profile", "mirror"
var _saved_menu := false
var _leaving := false
var _session := 0

var _layer: CanvasLayer
var _prompt: Label
var _profile_button: Button
var _axis_overlay: Control
var _axis_title: Label
var _axis_status: Label
var _profile_overlay: Control
var _name_input: LineEdit
var _about_input: TextEdit
var _profile_status: Label
var _logout_button: Button
var _logout_dialog: Control


func _ready() -> void:
	_session = Global.session_version
	if get_parent().has_signal("player_spawned"):
		get_parent().player_spawned.connect(_on_player_spawned)
	for zone in zones.get_children():
		zone.activated.connect(_activate)
	_build_ui()


func _on_player_spawned(body: CharacterBody2D) -> void:
	player = body
	nearest = null


func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "CustomizationUI"
	_layer.layer = 20
	add_child(_layer)

	_prompt = Label.new()
	_prompt.name = "InteractionPrompt"
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.add_theme_font_override("font", WoodPanel.PIXEL_FONT)
	_prompt.add_theme_font_size_override("font_size", 22)
	_prompt.add_theme_color_override("font_color", LobbyStyle.INK)
	_prompt.add_theme_stylebox_override("normal", LobbyStyle.box(LobbyStyle.PAPER, 6))
	_layer.add_child(_prompt)
	_prompt.hide()

	_profile_button = LobbyStyle.button("Profile [P]")
	_profile_button.name = "ProfileButton"
	_layer.add_child(_profile_button)
	_profile_button.pressed.connect(_on_profile_button_pressed)
	get_viewport().size_changed.connect(_place_profile_button)
	_place_profile_button()

	_build_axis_panel()
	_build_profile_panel()
	LobbyStyle.apply_tree.call_deferred(_profile_overlay)


func _on_profile_button_pressed() -> void:
	if modal == "profile":
		close()
	else:
		_show_profile()


func _place_profile_button() -> void:
	_profile_button.reset_size()
	var viewport_size := get_viewport().get_visible_rect().size
	_profile_button.position = Vector2(viewport_size.x - _profile_button.size.x - 20, 16)


func _make_overlay() -> Control:
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.15, 0.08, 0.04, 0.28)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)
	overlay.hide()
	return overlay


func _make_status() -> Label:
	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	WoodPanel.apply_status_label(status)
	return status


func _set_status(status: Label, text: String, color: Color) -> void:
	if status == null:
		return
	status.text = text
	status.add_theme_color_override("font_color", color)


func _build_axis_panel() -> void:
	_axis_overlay = _make_overlay()
	_layer.add_child(_axis_overlay)
	_creator = CreatorPanel.new()
	_axis_overlay.add_child(_creator)
	_creator.close_requested.connect(close)
	_axis_title = _creator.title_label
	_axis_status = _creator.status


func _build_profile_panel() -> void:
	_profile_overlay = _make_overlay()
	_layer.add_child(_profile_overlay)
	var center := CenterContainer.new()
	_profile_overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var card := WoodPanel.new()
	card.custom_minimum_size.x = 640
	center.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	card.add_child(column)
	var heading := Label.new()
	heading.text = "Profile"
	WoodPanel.apply_panel_title_style(heading)
	column.add_child(heading)
	var username_caption := Label.new()
	username_caption.text = "Account"
	WoodPanel.apply_card_detail_style(username_caption)
	column.add_child(username_caption)
	var username_value := Label.new()
	WoodPanel.apply_status_label(username_value)
	username_value.add_theme_color_override("font_color", WoodPanel.TEXT_SECONDARY)
	username_value.text = "%s  -  %s" % [Global.username, Global.email] if Global.email != "" else Global.username
	column.add_child(username_value)
	var name_caption := Label.new()
	name_caption.text = "Display Name"
	WoodPanel.apply_card_detail_style(name_caption)
	column.add_child(name_caption)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	column.add_child(name_row)
	_name_input = LineEdit.new()
	_name_input.custom_minimum_size.x = 420
	_name_input.text = Global.display_name
	WoodPanel.apply_field_style(_name_input)
	name_row.add_child(_name_input)
	var save_name := Button.new()
	save_name.text = "Save"
	save_name.set_script(WOOD_BUTTON)
	name_row.add_child(save_name)
	save_name.pressed.connect(_on_save_name)
	var about_caption := Label.new()
	about_caption.text = "About Me  (saved on this device)"
	WoodPanel.apply_card_detail_style(about_caption)
	column.add_child(about_caption)
	_about_input = TextEdit.new()
	_about_input.custom_minimum_size = Vector2(560, 96)
	_about_input.text = Global.about_me
	_about_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = WoodPanel.INPUT_BG
	input_style.border_color = WoodPanel.INPUT_BORDER
	input_style.set_border_width_all(2)
	input_style.set_corner_radius_all(2)
	input_style.content_margin_left = 10
	input_style.content_margin_right = 10
	input_style.content_margin_top = 8
	input_style.content_margin_bottom = 8
	_about_input.add_theme_stylebox_override("normal", input_style)
	_about_input.add_theme_stylebox_override("focus", input_style)
	_about_input.add_theme_font_override("font", WoodPanel.PIXEL_FONT)
	_about_input.add_theme_font_size_override("font_size", WoodPanel.SIZE_FIELD)
	_about_input.add_theme_color_override("font_color", WoodPanel.TEXT_COLOR)
	column.add_child(_about_input)
	var about_row := HBoxContainer.new()
	about_row.add_theme_constant_override("separation", 8)
	column.add_child(about_row)
	var save_about := Button.new()
	save_about.text = "Save About"
	save_about.set_script(WOOD_BUTTON)
	about_row.add_child(save_about)
	save_about.pressed.connect(_on_save_about)
	_profile_status = _make_status()
	column.add_child(_profile_status)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	_logout_button = Button.new()
	_logout_button.text = "Log Out"
	_logout_button.set_script(WOOD_BUTTON)
	buttons.add_child(_logout_button)
	_logout_button.pressed.connect(_on_logout_pressed)
	var close_button := Button.new()
	close_button.text = "Close [Esc]"
	close_button.set_script(WOOD_BUTTON)
	buttons.add_child(close_button)
	close_button.pressed.connect(close)


func _process(_delta: float) -> void:
	if _session != Global.session_version:
		_session = Global.session_version
		close()
	nearest = null
	if player == null or not is_instance_valid(player):
		player = get_parent().get_node_or_null("LobbyPlayer")
	if player == null or modal != "" or _leaving or GameState.menu_open:
		_prompt.hide()
		return
	var distance := INF
	var feet := player.global_transform * Vector2(0, 80)
	for zone in zones.get_children():
		if zone.available_to(player):
			var candidate := feet.distance_squared_to(zone.global_position)
			if candidate < distance:
				distance = candidate
				nearest = zone
	_prompt.visible = nearest != null
	if nearest != null:
		_prompt.text = nearest.prompt
		_prompt.reset_size()
		var screen := get_viewport().get_canvas_transform() * player.global_position
		_prompt.position = screen + Vector2(-_prompt.size.x / 2.0, -125)
		_prompt.position = _prompt.position.clamp(Vector2(12, 12), get_viewport_rect().size - _prompt.size - Vector2(12, 12))


func _unhandled_key_input(event: InputEvent) -> void:
	if _leaving or event.is_echo():
		return
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_P:
		if modal == "profile":
			close()
		elif modal == "":
			_show_profile()
		get_viewport().set_input_as_handled()
		return
	if modal == "" and not GameState.menu_open and nearest != null and event.is_action_pressed("interact"):
		nearest.activate(player)
		get_viewport().set_input_as_handled()


func _activate(action: StringName) -> void:
	if modal != "" or _leaving:
		return
	if action == &"leave":
		_leave()
		return
	if action == &"character":
		_show_axis("character")
		return
	if action == &"mirror":
		_show_axis("mirror")
		return


func _show_axis(kind: String) -> void:
	if modal != "": close()
	_saved_menu = GameState.menu_open
	GameState.menu_open = true
	if player != null: player.velocity = Vector2.ZERO
	modal = kind
	_axis_overlay.show()
	_creator.begin(kind)
	_axis_title = _creator.title_label
	_axis_status = _creator.status


func _show_profile() -> void:
	if _leaving:
		return
	if modal != "":
		close()
	_saved_menu = GameState.menu_open
	GameState.menu_open = true
	if player != null:
		player.velocity = Vector2.ZERO
	modal = "profile"
	_name_input.text = Global.display_name
	_about_input.text = Global.about_me
	_set_status(_profile_status, "", WoodPanel.TEXT_SECONDARY)
	_logout_button.visible = Global.is_logged_in()
	_profile_overlay.show()
	_name_input.grab_focus()


func _on_save_name() -> void:
	var new_name := _name_input.text.strip_edges()
	if new_name.is_empty():
		_set_status(_profile_status, "Display name cannot be empty.", WoodPanel.TEXT_ERROR)
		return
	if new_name == Global.display_name:
		_set_status(_profile_status, "That is already your name.", WoodPanel.TEXT_SECONDARY)
		return
	if Global.is_logged_in():
		var response: Dictionary = await APIClient.update_profile({"display_name": new_name})
		if not bool(response.get("ok", false)):
			_set_status(_profile_status, APIClient.error_text(response), WoodPanel.TEXT_ERROR)
			return
		_set_status(_profile_status, "Display name updated.", WoodPanel.TEXT_SUCCESS)
	else:
		_set_status(_profile_status, "Saved on this device.", WoodPanel.TEXT_SECONDARY)
	Global.display_name = new_name
	Global.save_session()


func _on_save_about() -> void:
	Global.about_me = _about_input.text
	Global.save_session()
	_set_status(_profile_status, "About text saved on this device.", WoodPanel.TEXT_SECONDARY)


func _on_logout_pressed() -> void:
	if _logout_dialog == null:
		_logout_dialog = LOGOUT_DIALOG.instantiate()
		_layer.add_child(_logout_dialog)
	_logout_dialog.show_dialog()


func close() -> void:
	if modal == "" or _leaving:
		return
	if modal in ["character","mirror"] and _creator._saving and _creator._session==Global.session_version:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null:
		focus.release_focus()
	if _creator != null: _creator.cancel()
	_axis_overlay.hide()
	_profile_overlay.hide()
	modal = ""
	GameState.menu_open = _saved_menu


func _input(event: InputEvent) -> void:
	if _leaving or event.is_echo():
		return
	if modal != "" and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _leave() -> void:
	_leaving = true
	_prompt.hide()
	_axis_overlay.hide()
	_profile_overlay.hide()
	if player != null:
		player.velocity = Vector2.ZERO
	GameState.menu_open = false
	SceneManager.leave_character_customization()


func _exit_tree() -> void:
	if _creator != null: _creator.cancel()
	if modal != "":
		GameState.menu_open = _saved_menu
