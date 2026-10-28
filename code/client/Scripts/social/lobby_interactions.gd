extends Node2D
## One local interaction/modal at a time. No room membership or movement code.

const SOCIAL_SCENE := preload("res://Scenes/social_panel.tscn")
const SOCIAL_ADAPTER := preload("res://Scripts/social/lobby_social_panel.gd")
const Style := preload("res://Scripts/ui/lobby_theme.gd")
const WOOD_BUTTON := preload("res://Scripts/components/wood_button.gd")

@onready var player: CharacterBody2D = get_parent().get_node_or_null("LobbyPlayer")
@onready var zones: Node2D = $InteractionZones
const FRIEND_RANGE := 200.0
var nearby_friend := 0
var invitation_target := 0
var _inviting := false
var nearest: Area2D
var modal := ""
var social: VBoxContainer
var prompt := ""   ## the "[E] ..." hint now on the message line, or ""
var overlay: Control
var heading: Label
var dialogue: Label
var primary: Button
var close_button: Button
var _saved_menu := false
var _leaving := false
var _session := 0
var _card: PanelContainer


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
	_card = card
	card.theme = Style.theme()
	card.add_theme_stylebox_override("panel", UiSkin.panel())
	UiSkin.ink_text(card)
	card.custom_minimum_size = Vector2(1100, 720)
	center.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	card.add_child(column)
	heading = Label.new()
	WoodPanel.apply_panel_title_style(heading)
	var title_bar := PanelContainer.new()
	# The pack's maroon plank carries the title; the heading text stays cream.
	title_bar.add_theme_stylebox_override("panel", UiSkin.buy_sell())
	column.add_child(title_bar)
	var title_row := HBoxContainer.new(); title_bar.add_child(title_row)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL; title_row.add_child(heading)
	var dismiss := Style.button("X"); title_row.add_child(dismiss); dismiss.pressed.connect(close)
	heading.add_theme_font_size_override("font_size", 28)
	heading.add_theme_color_override("font_color", Color("fff0d9"))
	dialogue = Label.new()
	dialogue.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue.custom_minimum_size.x = 680
	WoodPanel.apply_status_label(dialogue)
	dialogue.add_theme_color_override("font_color", Style.INK)
	column.add_child(dialogue)
	social = SOCIAL_SCENE.instantiate()
	social.set_script(SOCIAL_ADAPTER)
	column.add_child(social)
	social.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	get_viewport().size_changed.connect(_fit_window)
	_fit_window.call_deferred()

func _fit_window() -> void:
	if _card == null: return
	var viewport := get_viewport_rect().size
	var factor := minf(1.0, minf((viewport.x - 40) / 1100.0, (viewport.y - 40) / 720.0))
	# Scale the full modal together so column widths and focus targets agree.
	var center := _card.get_parent() as CenterContainer
	center.scale = Vector2.ONE * factor
	center.size = viewport / factor


func _process(_delta: float) -> void:
	if _session != Global.session_version:
		_session = Global.session_version
		close()
	nearest = null
	nearby_friend = 0
	if not is_instance_valid(player):
		_set_prompt("")
		return
	if modal != "" or _leaving or GameState.menu_open or GameState.social_open:
		_set_prompt("")
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
	var friends := get_parent().get_node_or_null("OnlineFriends")
	var friend_distance := FRIEND_RANGE
	if friends != null:
		for id in friends.avatars:
			var avatar: Node2D = friends.avatars[id]
			var separation := feet.distance_to(avatar.global_position)
			if not avatar.is_queued_for_deletion() and separation < friend_distance:
				friend_distance = separation
				nearby_friend = int(id)
	if nearby_friend > 0:
		_set_prompt("[E] Talk to " + _friend_title(nearby_friend))
	else:
		_set_prompt(nearest.prompt if nearest != null else "")


## Interaction hints share the game's message line. Only a change is sent, so
## a hint held every frame does not re-lay out the line every frame.
func _set_prompt(text: String) -> void:
	if text == prompt:
		return
	prompt = text
	if text == "":
		HousePrompt.hide_text()
	else:
		HousePrompt.show_text(text)


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
			and (nearest != null or nearby_friend > 0) and event.is_action_pressed("interact") and not event.is_echo():
		if nearby_friend > 0:
			invitation_target = nearby_friend
			_activate(&"friend")
		else:
			nearest.activate(player)
		get_viewport().set_input_as_handled()


func _activate(action: StringName) -> void:
	if modal != "" or _leaving or not is_instance_valid(player):
		return
	_saved_menu = GameState.menu_open
	GameState.menu_open = true
	player.velocity = Vector2.ZERO
	modal = String(action)
	_set_prompt("")
	overlay.show()
	primary.disabled = false
	primary.show()
	dialogue.show()
	match action:
		&"friend":
			heading.text = _friend_title(invitation_target)
			dialogue.text = "Ask them to visit your farm?"
			primary.text = "Invite to my farm"
			primary.disabled = _inviting or GameState.is_visiting()
			if GameState.is_visiting(): dialogue.text = "Return to your own farm before sending an invitation."
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
			heading.text = "Enter your farm?"
			dialogue.text = "Leave the lobby and enter your own farm?"
			primary.text = "Enter My Farm"
	primary.grab_focus() if primary.visible else close_button.grab_focus()


func _primary() -> void:
	if _leaving:
		return
	if modal == "friend":
		_invite_friend()
	elif modal == "reception":
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
	_fit_window.call_deferred()

func _unhandled_input(event: InputEvent) -> void:
	if modal != "" or GameState.menu_open or GameState.social_open or _leaving: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var chosen: Area2D
		var closest := 160.0
		for zone in zones.get_children():
			var distance: float = zone.global_position.distance_to(get_global_mouse_position())
			if zone.available_to(player) and distance < closest: closest = distance; chosen = zone
		if chosen != null:
			chosen.activate(player)
			get_viewport().set_input_as_handled()


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
	_set_prompt("")
	if modal != "":
		GameState.menu_open = _saved_menu

func _friend_title(id: int) -> String:
	var friends := get_parent().get_node_or_null("OnlineFriends")
	if friends != null and friends.avatars.has(id):
		return friends.avatars[id].get_node("FriendName").text
	return "Friend"

func _invite_friend() -> void:
	if _inviting or invitation_target <= 0 or GameState.is_visiting(): return
	var friends := get_parent().get_node_or_null("OnlineFriends")
	if friends == null or not friends.avatars.has(invitation_target):
		dialogue.text = "This friend is no longer online."
		primary.disabled = true
		return
	var avatar: Node2D = friends.avatars[invitation_target]
	if (player.global_transform * Vector2(0, 80)).distance_to(avatar.global_position) > FRIEND_RANGE:
		dialogue.text = "Move closer to your friend to invite them."
		return
	_inviting = true
	primary.disabled = true
	dialogue.text = "Sending invitation..."
	var version := Global.session_version
	var target := invitation_target
	var response: Dictionary = await APIClient.invite_to_farm(target)
	if not is_inside_tree(): return
	_inviting = false
	if version != Global.session_version or modal != "friend" or target != invitation_target: return
	dialogue.text = "Invitation sent! They can accept it from Farm invitations." if response.get("ok", false) else APIClient.error_text(response)
	primary.disabled = bool(response.get("ok", false))
