extends SceneTree
## Headless validation for the customization room: scene structure, traced
## collisions, interaction zones, and the Create New / exit routes.

const ROOM := "res://Scenes/CustomizationLobby.tscn"
const SELECT := "res://Scenes/menus/CharacterSelectScreen.tscn"
const IMAGE_SIZE := Vector2(1672, 941)
const ZONE_ACTIONS := [&"mirror", &"character", &"leave"]

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		print("FAIL: ", message)


func _run() -> void:
	root.get_node("APIClient").base_url = "http://127.0.0.1:1"
	await _check_room_structure()
	await _check_legacy_player()
	await _check_walkability()
	await _check_in_room_panels()
	await _check_create_new_and_exit()
	print("CUSTOMIZATION_LOBBY_CHECK failures=", failures)
	quit(failures)


func _check_room_structure() -> void:
	root.get_node("Global").selected_character = "girl_b"
	var room: Node2D = (load(ROOM) as PackedScene).instantiate()
	root.add_child(room)
	await process_frame
	await process_frame

	var tile_map := room.get_node_or_null("OldLobbyTileMap") as TileMapLayer
	_expect(tile_map != null, "TileMapLayer background node exists")
	if tile_map != null:
		_expect(tile_map.get_used_cells().size() == 1, "background tile map holds one tile")
		_expect(tile_map.tile_set != null and tile_map.tile_set.get_source(0).get_texture_region_size() == Vector2i(IMAGE_SIZE),
				"tile covers the whole 1672x941 image")

	var background := room.get_node_or_null("LobbyBackground") as Sprite2D
	_expect(background != null and background.texture != null, "background sprite exists")
	if background != null and background.texture != null:
		_expect(background.texture.get_size() == IMAGE_SIZE, "background sprite uses the full image")
		_expect(background.centered == false, "background sprite is top-left anchored")
		_expect(background.z_index == -10, "background draws behind the player")

	var camera := room.get_node_or_null("Camera2D") as Camera2D
	_expect(camera != null, "camera exists")
	if camera != null:
		_expect(camera.limit_left == 0 and camera.limit_top == 0
				and camera.limit_right == int(IMAGE_SIZE.x) and camera.limit_bottom == int(IMAGE_SIZE.y),
				"camera limits match the room")
		_expect(camera.position_smoothing_enabled, "camera smoothing is enabled")
		_expect(camera.zoom.x >= 1.0 and camera.zoom.y >= 1.0, "camera zoom fits the room")

	var spawn := room.get_node_or_null("PlayerSpawn") as Marker2D
	_expect(spawn != null and spawn.position.x > 0 and spawn.position.y > 0, "player spawn marker exists")

	var player := room.get_node_or_null("LobbyPlayer") as CharacterBody2D
	_expect(player != null, "selected character was spawned as LobbyPlayer")
	if player != null:
		_expect(player.global_position == spawn.position, "player spawned at the marker")
		_expect("require_world_connection" in player and player.require_world_connection == false,
				"player does not join world presence")
		_expect(player.get_node_or_null("CameraFollow") is RemoteTransform2D, "camera follows the player")
		var anim: AnimatedSprite2D = player.get("anim")
		_expect(anim != null and anim.animation == "idle_back", "player faces away from the camera")

	var collisions := room.get_node_or_null("StaticCollisions")
	_expect(collisions != null, "static collisions exist")
	if collisions != null:
		_expect(collisions.get_child_count() >= 8, "enough collision bodies were traced")
		for body in collisions.get_children():
			var footprint := body.get_node_or_null("Footprint") as CollisionPolygon2D
			_expect(footprint != null and footprint.polygon.size() >= 3,
					"%s has a polygon footprint" % body.name)

	var interactions := room.get_node_or_null("CustomizationInteractions")
	_expect(interactions != null, "interactions scene is instanced")
	if interactions != null:
		_expect(interactions.player == player, "interactions resolve the spawned player")
		var zones := interactions.get_node("InteractionZones")
		_expect(zones.get_child_count() == ZONE_ACTIONS.size(), "only character, mirror and exit zones exist")
		var found: Array = []
		for zone in zones.get_children():
			found.append(zone.action)
			var detection := zone.get_node_or_null("Detection") as CollisionShape2D
			_expect(detection != null and detection.shape is RectangleShape2D,
					"%s uses a rectangle detection shape" % zone.name)
			_expect(zone.collision_mask == 1, "%s detects the player layer" % zone.name)
		for action in ZONE_ACTIONS:
			_expect(action in found, "zone %s exists" % String(action))

	room.queue_free()
	await process_frame
	await process_frame


func _check_legacy_player() -> void:
	# The default guest character uses the old player.gd, which has no facing
	# or require_world_connection exports; the room must spawn it anyway.
	root.get_node("Global").selected_character = ""
	var room: Node2D = (load(ROOM) as PackedScene).instantiate()
	root.add_child(room)
	await process_frame
	await process_frame
	var player := room.get_node_or_null("LobbyPlayer") as CharacterBody2D
	_expect(player != null and player.scene_file_path.ends_with("player1.tscn"),
			"legacy player1 scene spawns without the chara_player API")
	room.queue_free()
	await process_frame
	await process_frame


func _blocked(point: Vector2, world: World2D, exclude: Array[RID] = []) -> bool:
	var params := PhysicsPointQueryParameters2D.new()
	params.position = point
	params.collide_with_bodies = true
	params.collide_with_areas = false
	params.exclude = exclude
	return world.direct_space_state.intersect_point(params).size() > 0


func _check_walkability() -> void:
	var room: Node2D = (load(ROOM) as PackedScene).instantiate()
	root.add_child(room)
	await process_frame
	await process_frame
	var world := room.get_world_2d()
	# The room's own player body stands on the spawn point; only probe the walls.
	var player := room.get_node_or_null("LobbyPlayer") as CharacterBody2D
	var exclude: Array[RID] = []
	if player != null:
		exclude.append(player.get_rid())

	for point: Vector2 in [Vector2(836, 640), Vector2(420, 430), Vector2(600, 420),
			Vector2(836, 420), Vector2(1250, 460), Vector2(838, 850),
			Vector2(1100, 600), Vector2(300, 600)]:
		_expect(not _blocked(point, world, exclude), "walkable probe %s is open" % str(point))

	for point: Vector2 in [Vector2(836, 120), Vector2(200, 200), Vector2(1400, 200),
			Vector2(60, 600), Vector2(1620, 600), Vector2(300, 850),
			Vector2(1400, 850), Vector2(838, 930), Vector2(225, 430), Vector2(1250, 360)]:
		_expect(_blocked(point, world, exclude), "blocked probe %s is solid" % str(point))

	room.queue_free()
	await process_frame
	await process_frame


func _check_in_room_panels() -> void:
	# Offline (base_url points at a dead port): switches and profile saves are local.
	var global := root.get_node("Global")
	global.selected_character = "girl_b"
	var previous_name: String = global.display_name
	var previous_about: String = global.about_me
	global.hair_style = 0
	global.cloth_style = 0
	global.skin_tone = 0
	global.save_session()
	var room: Node2D = (load(ROOM) as PackedScene).instantiate()
	root.add_child(room)
	await process_frame
	await process_frame
	var interactions := room.get_node("CustomizationInteractions")
	var lobby: Node2D = room

	# Original character selection; obsolete generated appearance controls removed.
	interactions._activate(&"character")
	_expect(interactions.modal == "character", "character customization opens selection")
	_expect(root.get_node("GameState").menu_open, "character selection gates movement")
	_expect(interactions._axis_title.text == "Characters", "station opens the original six character choices")
	interactions.close()
	_expect(interactions.modal == "", "character panel closes")
	_expect(not root.get_node("GameState").menu_open, "close restores movement")

	interactions._activate(&"mirror")
	_expect(interactions.modal == "mirror", "mirror opens current character")
	_expect(not interactions._creator.options.visible and not interactions._creator._save.visible, "mirror is read-only")
	interactions.close()

	# Live appearance changes apply to Global and emit signals.
	global.set_appearance(2, 4, 3)
	_expect(global.hair_style == 2, "hair style saved")
	_expect(global.cloth_style == 4, "cloth style saved")
	_expect(global.skin_tone == 3, "skin tone saved")
	_expect(global.hair_color() == global.HAIR_COLORS[2], "hair color accessor works")
	_expect(global.cloth_color() == global.CLOTH_COLORS[4], "cloth color accessor works")
	_expect(global.skin_color() == global.SKIN_TONES[3], "skin color accessor works")

	# Profile panel: offline name/about saves stay on this device.
	interactions._show_profile()
	_expect(interactions.modal == "profile", "profile panel opens")
	interactions._name_input.text = "Wanderer"
	interactions._on_save_name()
	_expect(global.display_name == "Wanderer", "offline display name save works")
	interactions._about_input.text = "Passing through the salon."
	interactions._on_save_about()
	_expect(global.about_me == "Passing through the salon.", "about text saved locally")
	interactions._name_input.text = "   "
	interactions._on_save_name()
	_expect(global.display_name == "Wanderer", "empty name is rejected")

	# Offline the Log Out button is hidden; the confirm dialog still opens on demand.
	_expect(not interactions._logout_button.visible, "logout button hidden while logged out")
	interactions._on_logout_pressed()
	await process_frame
	var dialog: Control = interactions._logout_dialog
	_expect(dialog != null and dialog.visible, "logout confirmation dialog opens")
	if dialog != null:
		dialog._on_cancel()
		await create_timer(0.35).timeout
		_expect(not dialog.visible, "cancelling hides the logout dialog")
	interactions.close()

	global.display_name = previous_name
	global.about_me = previous_about
	global.hair_style = 0
	global.cloth_style = 0
	global.skin_tone = 0
	global.save_session()
	room.queue_free()
	await process_frame
	await process_frame


func _check_create_new_and_exit() -> void:
	root.get_node("Global").selected_character = "girl_b"
	var select_screen: Control = (load(SELECT) as PackedScene).instantiate()
	root.add_child(select_screen)
	await process_frame
	await process_frame

	var grid: GridContainer = select_screen.get_node("%CharacterGrid")
	var create_card: Button = grid.get_child(grid.get_child_count() - 1)
	_expect(create_card.has_method("get_character_id") and create_card.get_character_id() == "",
			"last card on character select is Create New")
	create_card.button_pressed = true
	select_screen._on_confirm()
	await create_timer(1.0).timeout

	var room := current_scene
	_expect(room != null and room.scene_file_path == ROOM, "Create New opens the customization room")
	if room != null:
		var player := room.get_node_or_null("LobbyPlayer") as CharacterBody2D
		_expect(player != null and player.scene_file_path.ends_with("charagirlB.tscn"),
				"the selected character was spawned")

		if player != null:
			room.get_node("CustomizationInteractions")._activate(&"leave")
			await create_timer(1.0).timeout
			_expect(current_scene != null and current_scene.scene_file_path == SELECT,
					"exit returns to character select")
