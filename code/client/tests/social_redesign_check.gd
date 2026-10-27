extends SceneTree
## Isolated UI fixtures verify layout/state; they do not simulate live audio.
var failures := 0
var view: SubViewport
var stage: Node2D
var output := "res://../../test-output/ui-redesign"

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value: failures += 1; push_error(message)
func settle() -> void:
	await process_frame
	await process_frame
func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	view.get_texture().get_image().save_png(output.path_join(name + ".png"))

func run() -> void:
	root.get_node("APIClient").base_url = "http://127.0.0.1:1/ui-fixtures"
	var session := root.get_node("Global")
	session.token = ""; session.player_id = 1; session.selected_character = "girl_a"
	var state := root.get_node("GameState")
	state.menu_open = false; state.social_open = false
	view = SubViewport.new(); view.size = Vector2i(1920,1088); view.world_2d = World2D.new(); view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(view)
	var scene_owner := Node2D.new(); root.add_child(scene_owner); current_scene = scene_owner
	stage = Node2D.new(); view.add_child(stage)
	var background := ColorRect.new(); background.size = Vector2(1920,1088); background.color = Color("50634c"); stage.add_child(background)
	var actor: CharacterBody2D = load("res://Scenes/charagirlA.tscn").instantiate(); actor.position = Vector2(960,480); actor.require_world_connection = false; stage.add_child(actor); actor.set_physics_process(false)
	var hud: Node = load("res://Scenes/world_hud.tscn").instantiate(); stage.add_child(hud)
	state.economy = {"aura_balance":250}; state.experience = {"level":6,"title":"Wanderer","current_xp":80,"xp_span":120}; hud._counters()
	await settle()
	var nearby: Node = hud.proximity_social
	check(nearby._toggle.text == "Nearby · 0" and not nearby._scroll.visible, "Persistent empty Nearby pill")
	check(nearby._panel.position.y > 900, "Nearby is bottom-left")
	check(hud.get_node("%SocialButton").get_global_rect().position.x > 1400, "Social action is top-right")
	check(hud.find_child("InventoryButton",true,false) == null, "Inventory remains at CDS without a HUD shortcut")
	await shot("main-hud")
	nearby._proximity({"nearby":[{"player_id":21,"username":"Willow","distance":52,"friend":true,"can_voice":true},{"player_id":22,"username":"Rowan","distance":96,"can_voice":false}]})
	check(not nearby._scroll.visible, "Presence does not auto-open Nearby")
	nearby._toggle.pressed.emit(); await settle()
	check(nearby._peer_cards.get_child_count() == 2, "Nearby has player cards")
	check(nearby._panel.get_global_rect().end.y <= 1088, "Nearby fits the viewport")
	await shot("nearby")
	nearby.open_voice(); await settle()
	check(nearby.voice.connection_state() == "Not joined" and nearby.voice._capture == null, "Voice requires explicit Join and does not capture")
	check(nearby._voice_panel.mode.selected == 0, "Push to Talk is default")
	nearby.voice.status_changed.emit("Microphone is off. Join Voice, then hold V to talk.")
	root.get_node("APIClient").realtime.connection_changed.emit(true)
	check(nearby._voice_panel.detail.text.begins_with("Microphone"), "Gameplay connectivity cannot overwrite voice state")
	await shot("voice")
	nearby._dismiss(); await settle()
	check(not state.social_open, "Closing Nearby restores input")
	await hud.switch_panel("settings"); await settle()
	await create_timer(0.45).timeout
	check(not nearby._panel.visible, "Settings owns the modal without Nearby overlapping")
	await shot("settings")
	await hud.switch_panel("settings"); await settle()
	check(nearby._panel.visible and not state.social_open, "Closing Settings restores the compact HUD")
	hud.queue_free(); actor.queue_free(); background.queue_free(); await settle()
	var lobby: Node = load("res://Scenes/SocialLobby.tscn").instantiate(); view.add_child(lobby)
	await settle()
	var host: Node = lobby.get_node("LobbyInteractions")
	check(host.zones.has_node("InvitationBoard") and host.zones.has_node("NoticeBoard") and not host.zones.has_node("Wardrobe"), "Social hub has social stations without duplicate customization")
	await shot("social-lobby")
	host.modal = "social"; host.overlay.show(); host.heading.text = "Social"; host.dialogue.hide(); host.primary.hide()
	var social: Node = host.social
	# The service suite exercises show_section against a real backend. Seed this
	# visual fixture without starting intentionally unreachable HTTP requests.
	social.show(); social.panel.show(); social.friends.show(); social.chat.hide(); social.notifications.hide()
	social._section = "requests"; social.view.select(1); social._section_title.text = "Friend Requests"; social._request_tabs.show(); social._elapsed = -1000
	social._update_nav()
	social._rows = [{"id":21,"username":"Willow","requested_by":21,"character_code":"girl_b","online":true,"level":6,"title":"Wanderer"},{"id":22,"username":"Rowan","requested_by":1,"character_code":"boy_b"}]
	social._revision += 1; social._loading = false; social.status.text = "1 incoming request"
	social.people.clear(); social.people.add_item("Willow"); social.people.add_item("Rowan"); social._actions(); await settle()
	check(social._cards.get_child_count() == 1, "Incoming and sent requests are separated")
	social._on_card_selected(0); await settle()
	check(not social._acting and social._selected().username == "Willow", "Profile selection does not trigger Accept")
	check(social.get_node("SocialColumns/Navigation").size.x >= 170, "Social has persistent sidebar navigation")
	await shot("social-requests")
	social._sent.pressed.emit(); await settle(); check(social._cards.get_child_count() == 1 and social._cards.get_child(0).name == "PlayerCard_1", "Sent requests retain original target identity")
	social._incoming.pressed.emit(); social._on_card_selected(0); await settle()
	# The same responsive window remains inside a smaller canvas.
	view.size = Vector2i(960,640); host._fit_window(); await settle()
	check(Rect2(Vector2.ZERO,Vector2(960,640)).encloses(host._card.get_global_rect()), "Social modal fits smaller viewports")
	await shot("social-compact")
	view.size = Vector2i(1920,1088); host._fit_window(); await settle()
	host.close(); lobby.queue_free(); await settle(); state.menu_open=false; state.social_open=false
	var room: Node = load("res://Scenes/CustomizationLobby.tscn").instantiate(); view.add_child(room); await settle()
	var wardrobe: Node = room.get_node("CustomizationInteractions")
	wardrobe._activate(&"character"); await settle()
	check(wardrobe._creator.options.visible and wardrobe._creator.options.get_child_count() == 6, "Wardrobe offers the six available base characters")
	wardrobe._creator._choose("boy_a"); check(session.selected_character == "girl_a", "Draft appearance is not saved early")
	await shot("wardrobe")
	wardrobe.close(); check(session.selected_character == "girl_a", "Cancel restores saved appearance")
	current_scene = null
	view.queue_free(); scene_owner.queue_free()
	await create_timer(0.25).timeout
	# Let intentionally unreachable fixture HTTP requests release their awaiters
	# before shutdown; product/service tests use the real disposable backend.
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		var pending := false
		for node in root.get_node("APIClient").get_children():
			if node is HTTPRequest: pending = true
		if not pending: break
		await create_timer(0.1).timeout
	print("SOCIAL_REDESIGN_CHECK failures=",failures)
	quit(failures)
