extends Node2D
## One local interaction/modal at a time. No room membership or movement code.

const SOCIAL_SCENE := preload("res://Scenes/social_panel.tscn")
const SOCIAL_ADAPTER := preload("res://Scripts/social/lobby_social_panel.gd")
const Style := preload("res://Scripts/ui/lobby_theme.gd")
const WOOD_BUTTON := preload("res://Scripts/components/wood_button.gd")

@onready var player: CharacterBody2D = get_parent().get_node_or_null("LobbyPlayer")
@onready var zones: Node2D = $InteractionZones
var nearest: Area2D
var modal := ""
var social: VBoxContainer
var prompt: Label
var overlay: Control
var heading: Label
var dialogue: Label
var primary: Button
var close_button: Button
var _saved_menu := false
var _leaving := false
var _session := 0


func _ready() -> void:
	_session = Global.session_version
	get_parent().player_spawned.connect(_on_player_spawned)
	for zone in zones.get_children():
		zone.activated.connect(_activate)
	_build_ui()


func _on_player_spawned(body: CharacterBody2D) -> void:
	player = body
	nearest = null


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "LobbyUI"
	layer.layer = 20
	add_child(layer)
	prompt = Label.new()
	prompt.name = "InteractionPrompt"
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt.add_theme_font_override("font", WoodPanel.PIXEL_FONT)
	prompt.add_theme_font_size_override("font_size", 22)
	prompt.add_theme_color_override("font_color", Style.INK)
	prompt.add_theme_stylebox_override("normal", Style.box(Style.PAPER, 6))
	prompt.add_theme_color_override("font_outline_color", Color("40291f"))
	prompt.add_theme_constant_override("outline_size", 0)
	layer.add_child(prompt)
	prompt.hide()
	overlay = Control.new()
	overlay.name = "DialogueOverlay"
	layer.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.15, 0.08, 0.04, 0.28)
	overlay.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var card := PanelContainer.new()
	card.theme = Style.theme()
	card.add_theme_stylebox_override("panel", Style.box(Style.PAPER, 18))
	card.custom_minimum_size.x = 940
	center.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	card.add_child(column)
	heading = Label.new()
	WoodPanel.apply_panel_title_style(heading)
	var title_bar := PanelContainer.new()
	title_bar.add_theme_stylebox_override("panel", Style.box(Style.MAROON, 10))
	column.add_child(title_bar)
	title_bar.add_child(heading)
	heading.add_theme_font_size_override("font_size", 28)
	heading.add_theme_color_override("font_color", Color("fff0d9"))
	dialogue = Label.new()
	dialogue.custom_minimum_size.x = 680
	WoodPanel.apply_status_label(dialogue)
	dialogue.add_theme_color_override("font_color", Style.INK)
	column.add_child(dialogue)
	social = SOCIAL_SCENE.instantiate()
	social.set_script(SOCIAL_ADAPTER)
	column.add_child(social)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	column.add_child(buttons)
	primary = Style.button("Continue", true)
	buttons.add_child(primary)
	primary.pressed.connect(_primary)
	close_button = Style.button("Close [Esc]")
	buttons.add_child(close_button)
	close_button.pressed.connect(close)
	overlay.hide()


func _process(_delta: float) -> void:
	if _session != Global.session_version:
		_session = Global.session_version
		close()
	nearest = null
	if not is_instance_valid(player):
		prompt.hide()
		return
	if modal != "" or _leaving or GameState.menu_open or GameState.social_open:
		prompt.hide()
		return
	var distance := INF
	# Compare the same foot position against each overlapping detection zone.
	var feet := player.global_transform * Vector2(0, 80)
	for zone in zones.get_children():
		if zone.available_to(player):
			var candidate := feet.distance_squared_to(zone.global_position)
			if candidate < distance:
				distance = candidate
				nearest = zone
	prompt.visible = nearest != null
	if nearest != null:
		prompt.text = nearest.prompt
		prompt.reset_size()
		var screen := get_viewport().get_canvas_transform() * player.global_position
		prompt.position = screen + Vector2(-prompt.size.x / 2.0, -125)
		prompt.position = prompt.position.clamp(Vector2(12, 12), get_viewport_rect().size - prompt.size - Vector2(12, 12))


func _input(event: InputEvent) -> void:
	if _leaving or event.is_echo():
		return
	if modal != "" and event.is_action_pressed("ui_cancel"):
		var popup: PopupMenu = social.get_node("%More").get_popup()
		if popup.visible:
			popup.hide()
		else:
			close()
		get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	if modal == "" and not _leaving and not GameState.menu_open and not GameState.social_open \
			and nearest != null and event.is_action_pressed("interact") and not event.is_echo():
		nearest.activate(player)
		get_viewport().set_input_as_handled()


func _activate(action: StringName) -> void:
	if modal != "" or _leaving or not is_instance_valid(player):
		return
	_saved_menu = GameState.menu_open
	GameState.menu_open = true
	player.velocity = Vector2.ZERO
	modal = String(action)
	prompt.hide()
	overlay.show()
	primary.show()
	dialogue.show()
	match action:
		&"reception":
			heading.text = "Reception"
			dialogue.text = "Welcome to Wanderville! Looking for someone?"
			primary.text = "Find a Friend"
		&"friends":
			_open_section("friends")
		&"requests":
			_open_section("requests")
		&"invitations":
			_open_section("invitations")
		&"notifications":
			_open_section("notifications")
		&"leave":
			heading.text = "Return to Wanderville?"
			dialogue.text = "Ready to head back to the main world?"
			primary.text = "Return to world"
	primary.grab_focus() if primary.visible else close_button.grab_focus()


func _primary() -> void:
	if _leaving:
		return
	if modal == "reception":
		_open_section("search")
	elif modal == "leave":
		_leaving = true
		primary.disabled = true
		close_button.disabled = true
		# No logout, state reload, or room invention. The normal world restores its
		# existing authenticated transport and owned/visited world context itself.
		SceneManager.leave_social_lobby()


func _open_section(section: String) -> void:
	if not Global.is_logged_in():
		heading.text = "Sign in required"
		dialogue.text = "Sign in through the main game to search for friends and manage requests."
		primary.hide()
		close_button.grab_focus()
		return
	modal = "social"
	var titles := {
		"friends": "Friends",
		"requests": "Friend requests",
		"search": "Find a Friend",
		"invitations": "Farm invitations",
		"notifications": "Notifications",
	}
	heading.text = str(titles.get(section, "Social"))
	dialogue.text = "What's your friend's name?" if section == "search" else ""
	dialogue.visible = section == "search"
	primary.hide()
	social.show_section(section)


func close() -> void:
	if modal == "" or _leaving:
		return
	social.set_open(false)
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null:
		focus.release_focus()
	overlay.hide()
	modal = ""
	GameState.menu_open = _saved_menu


func _exit_tree() -> void:
	if modal != "":
		GameState.menu_open = _saved_menu
