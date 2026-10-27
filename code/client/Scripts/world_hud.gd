extends CanvasLayer

var active := ""
var _switching := false
var _notice_unread := 0
var _badges_polled := false
var _request_count := 0
var _toast_version := 0
var _error_version := 0


func _ready() -> void:
	var proximity_social := preload("res://Scripts/social/proximity_social.gd").new()
	add_child(proximity_social)
	for label in [%Balance, %ProgressText, %WorldLabel, %LevelToastText]:
		WoodPanel.apply_status_label(label)
	%Balance.add_theme_font_size_override("font_size", 18)
	%ProgressText.add_theme_font_size_override("font_size", 16)
	%WorldLabel.add_theme_font_size_override("font_size", 16)
	%ToastClose.pressed.connect(func() -> void: %LevelToast.hide())
	%SocialButton.pressed.connect(func() -> void: SceneManager.goto_social_lobby())
	%SocialButton.draw.connect(_draw_badge)
	%SettingsButton.pressed.connect(func() -> void: switch_panel("settings"))
	%SettingsButton.draw.connect(func() -> void: _draw_settings_icon(%SettingsButton))
	%Settings.closed.connect(func() -> void:
		active = ""
		GameState.social_open = false
	)
	GameState.economy_updated.connect(func(_data: Dictionary) -> void: _counters())
	GameState.experience_updated.connect(func(_data: Dictionary) -> void: _counters())
	GameState.level_advanced.connect(_show_level_up)
	GameState.backend_error.connect(_show_action_error)
	WoodPanel.apply_error_label(%ActionError)
	GameState.world_updated.connect(func(data: Dictionary) -> void:
		_world_label()
	)
	GameState.read_only_changed.connect(func(_value: bool) -> void: _world_label())
	GameState.session_updated.connect(func(_session: Dictionary) -> void: _world_label())
	# Being dropped from a visit changes which world every read must come from,
	# so the reload is triggered by the event rather than waiting for the poll.
	APIClient.realtime.visit_ended.connect(_visit_ended)
	APIClient.realtime.room_changed.connect(func(_room: String) -> void: GameState.refresh_gameplay())
	Global.session_changed.connect(_clear_account)
	_counters()
	if not Global.is_logged_in():
		GameState.load_dummy_inventory()  # TEMP offline test
	_world_label()
	var timer := Timer.new()
	timer.wait_time = 20.0
	timer.timeout.connect(_refresh_badges)
	add_child(timer)
	timer.start()
	_refresh_badges()


func _world_label() -> void:
	var state := "%s · %s" % [
		str(GameState.world_state.get("current_season", "")).capitalize(),
		str(GameState.world_state.get("weather", "")).capitalize(),
	]
	# While visiting, the world state on screen belongs to the host, so the label
	# has to say so or the player reads another player's farm as their own.
	%WorldLabel.text = ("Visiting · read-only · " + state) if GameState.read_only else state


func _visit_ended(message: String) -> void:
	_show_action_error(message)
	_world_label()
	# The session on this client still describes the visit that was just taken
	# away, so the authoritative one is fetched before anything else reads it.
	GameState.refresh_gameplay()


func switch_panel(kind: String) -> void:
	if _switching or GameState.menu_open:
		return
	_switching = true
	var next := "" if kind == active else kind
	if active == "settings" and not await %Settings.request_close():
		_switching = false
		return
	active = next
	GameState.social_open = active != ""
	if active == "settings":
		%Settings.show_overlay()
	_switching = false


func _input(event: InputEvent) -> void:
	if active != "" and event.is_action_pressed("ui_cancel"):
		switch_panel("")
		get_viewport().set_input_as_handled()


func _counters() -> void:
	var xp: Dictionary = GameState.experience
	var level := int(xp.get("level", 1))
	var maximum := bool(xp.get("max_level", false))
	%Balance.text = "Aura %d\nLevel %d — %s" % [int(GameState.economy.get("aura_balance", 0)), level, xp.get("title", "Villager")]
	%ProgressText.text = "Max level" if maximum else "%d / %d XP toward Level %d" % [int(xp.get("current_xp", 0)), int(xp.get("xp_span", 0)), level + 1]
	%XP.max_value = 1.0 if maximum else maxf(1.0, float(xp.get("xp_span", 1)))
	%XP.value = 1.0 if maximum else float(xp.get("current_xp", 0))
	%XP.tooltip_text = "Total XP: %d" % int(xp.get("total_xp", 0))
	%ProgressText.tooltip_text = %XP.tooltip_text


func _show_level_up(previous: Dictionary, current: Dictionary) -> void:
	AudioManager.play("level_up")
	var old_level := int(previous.get("level", 1))
	var level := int(current.get("level", 1))
	var gained_slots := int(current.get("slot_increment", 0)) - int(previous.get("slot_increment", 0))
	var aura := 0
	for reward in current.get("rewards", []):
		if int(reward["level"]) > old_level and int(reward["level"]) <= level:
			aura += int(reward.get("aura", 0))
	var lines := PackedStringArray(["Level %d — %s" % [level, current.get("title", "")]])
	if gained_slots > 0:
		lines.append("+%d inventory slots" % gained_slots)
	if aura > 0:
		lines.append("+%d Aura awarded" % aura)
	var unlocked := PackedStringArray()
	for item in current.get("unlocked_items", []):
		if int(item.get("required_level", 1)) > old_level:
			unlocked.append(str(item["name"]))
	if not unlocked.is_empty():
		var preview := ", ".join(unlocked.slice(0, 3))
		lines.append("Unlocked: " + preview + (" (+%d more)" % (unlocked.size() - 3) if unlocked.size() > 3 else ""))
	%LevelToastText.text = "\n".join(lines)
	%LevelToastText.tooltip_text = ", ".join(unlocked)
	%LevelToast.show()
	_toast_version += 1
	var version := _toast_version
	await get_tree().create_timer(9.0).timeout
	if version == _toast_version:
		%LevelToast.hide()


func _show_action_error(message: String) -> void:
	AudioManager.play("notification")
	%ActionError.text = message
	%ActionError.show()
	_error_version += 1
	var version := _error_version
	await get_tree().create_timer(8.0).timeout
	if version == _error_version:
		%ActionError.hide()


func _refresh_badges() -> void:
	if not Global.is_logged_in():
		return
	# One bounded inbox read; the Social Lobby recomputes the rest when opened.
	var response: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_GET, "/notifications?limit=1")
	if response.get("ok", false) and not response.get("stale", false):
		var unread := int(APIClient.data_of(response).get("unread_count", 0))
		# Only a notice that arrived while playing makes a sound. The first poll
		# of a session just reports the backlog, which must stay silent.
		if _badges_polled and unread > _notice_unread:
			AudioManager.play("notification")
		_badges_polled = true
		_notice_unread = unread
	response = await APIClient.authenticated(HTTPClient.METHOD_GET, "/social/requests")
	if response.get("ok", false) and not response.get("stale", false):
		_request_count = 0
		for row in APIClient.data_of(response):
			if int(row.get("requested_by", 0)) != Global.player_id:
				_request_count += 1
	%SocialButton.queue_redraw()


func _clear_account() -> void:
	_toast_version += 1
	_error_version += 1
	%LevelToast.hide()
	%ActionError.hide()
	_notice_unread = 0
	_request_count = 0
	_badges_polled = false
	%SocialButton.queue_redraw()
	active = ""
	%Settings.hide()
	GameState.social_open = false
	_world_label()


func _draw_badge() -> void:
	var count := _notice_unread + _request_count
	if count <= 0:
		return
	var corner := Vector2(%SocialButton.size.x - 12, 12)
	%SocialButton.draw_circle(corner, 10, Color(0.65, 0.18, 0.12))
	%SocialButton.draw_string(WoodPanel.PIXEL_FONT, corner + Vector2(-10, 4), str(mini(count, 99)), HORIZONTAL_ALIGNMENT_CENTER, 20, 12, Color.WHITE)


func _draw_settings_icon(button: Button) -> void:
	var c := button.size / 2.0
	var ink := WoodPanel.TEXT_COLOR
	button.draw_arc(c, 9, 0, TAU, 20, ink, 2)
	button.draw_circle(c, 3, ink)
	for i in 8:
		var direction := Vector2.RIGHT.rotated(i * TAU / 8)
		button.draw_line(c + direction * 9, c + direction * 14, ink, 3)
