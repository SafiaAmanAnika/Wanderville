extends SceneTree
## Exercise the actual lobby scenes with all six saved character selections.
const ROOMS := ["res://Scenes/SocialLobby.tscn", "res://Scenes/CustomizationLobby.tscn"]
var failures := 0
var spawned := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	var session := root.get_node("Global")
	root.get_node("APIClient").base_url = "http://127.0.0.1:1/lobby-spawner-test"
	session.token = "isolated-spawner-fixture"
	session.player_id = 918273
	var version: int = session.session_version
	for room_path in ROOMS:
		for code in session.CHARACTERS:
			if session.CHARACTERS[code].folder == "": continue
			session.selected_character = code
			session.modular_look = {"preset":"retired-generated-look", "skin":3}
			var saved: Dictionary = session.modular_look.duplicate(true)
			var room: Node2D = load(room_path).instantiate()
			root.add_child(room)
			await process_frame
			await physics_frame
			var player: CharacterBody2D = room.get_node_or_null("LobbyPlayer")
			check(player != null, "Selected player scene loads: " + code)
			if player == null:
				room.queue_free()
				quit(1)
				return
			var social: bool = room_path.ends_with("SocialLobby.tscn")
			var host: Node = room.get_node("LobbyInteractions" if social else "CustomizationInteractions")
			check(player.scene_file_path == session.CHARACTER_SCENES[code], "Selected character controller spawns in " + room_path)
			check(player.position == room.get_node("PlayerSpawn").position, "PlayerSpawn marker is respected")
			check(player.scale == Vector2(0.75, 0.75), "Existing lobby player scale is retained")
			check(not player.require_world_connection, "Authenticated lobby movement does not wait for campus transport")
			check(not player.has_node("Appearance") and player.anim.visible, "Original sprite stays visible; retired appearance metadata is ignored")
			check(host.player == player, "Interactions resolve the spawned player before use")
			check(get_nodes_in_group("player").size() == 1, "Exactly one player is active")
			var camera: Camera2D = room.get_node("Camera2D")
			var follow: RemoteTransform2D = player.get_node("CameraFollow")
			check(follow.get_node(follow.remote_path) == camera and not follow.update_scale, "Camera follows the selected player independently of scale")
			check(room.get_node("StaticCollisions").get_child_count() == (24 if social else 8), "Existing collision bodies are retained")
			if social and code == "boy_c" and DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				DirAccess.make_dir_recursive_absolute("D:/GitHubProjects/Wanderville/test-output/lobby-spawner")
				var capture_dir := OS.get_environment("TEST_LOBBY_OUTPUT")
				if capture_dir.is_empty(): capture_dir = "user://lobby-spawner"
				DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_dir))
				root.get_texture().get_image().save_png(capture_dir.path_join("social-original-boy-c.png"))
			var spot := player.position
			Input.action_press("ui_right")
			for tick in 6: await physics_frame
			Input.action_release("ui_right")
			await physics_frame
			check(absf(player.position.x - spot.x - 30.0) < 11.0, "Selected controller moves at the existing 300 units per second")
			spot = player.position
			var replacement: CharacterBody2D = room.respawn_player()
			check(replacement != player and replacement.position == spot, "Respawn preserves the current position")
			check(host.player == replacement and get_nodes_in_group("player").size() == 1, "Respawn rebinds interactions without duplicate players")
			check(session.modular_look == saved and session.token == "isolated-spawner-fixture" and session.session_version == version, "Spawn and respawn preserve appearance and session")
			spawned += 1
			room.queue_free()
			await process_frame
	# The original farmer remains a valid fallback and must also walk locally.
	session.selected_character = "farmer_female"
	session.modular_look = {}
	var fallback: Node2D = load(ROOMS[0]).instantiate()
	root.add_child(fallback)
	await process_frame
	check(fallback.player.scene_file_path.ends_with("player1.tscn") and not fallback.player.require_world_connection, "Original farmer fallback also spawns with local lobby movement")
	fallback.queue_free()
	await process_frame
	print("LOBBY_SPAWNER_CHECK failures=", failures, " selected_character_room_pairs=", spawned)
	quit(failures)
