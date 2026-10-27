extends Node2D
## Online-friend presence portraits; room positions are local, not campus coordinates.
const Preview := preload("res://Scripts/customization/character_preview.gd")
const Style := preload("res://Scripts/ui/lobby_theme.gd")
const REFRESH_SECONDS := 5.0
const FLOOR := Rect2(180, 430, 1560, 350)
const SPACING := 110.0
var avatars: Dictionary = {}
var _elapsed := 0.0
var _refreshing := false
var _session := -1
var _previous_standalone := false
var _previous_pause := false
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_session = Global.session_version
	_previous_standalone = APIClient.realtime.standalone_enabled
	_previous_pause = APIClient.realtime.pause_movement
	# Keep the account online, but never send room coordinates as campus movement.
	APIClient.realtime.standalone_enabled = true
	APIClient.realtime.pause_movement = true
	Global.session_changed.connect(_session_changed)
	_refresh.call_deferred()

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= REFRESH_SECONDS:
		_elapsed = 0.0
		_refresh()

func _session_changed() -> void:
	_session = Global.session_version
	_sync_friends([])
	_elapsed = REFRESH_SECONDS

func _refresh() -> void:
	if not Global.is_logged_in():
		_sync_friends([])
		return
	if _refreshing: return
	_refreshing = true
	var version := Global.session_version
	var response: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_GET, "/social/friends")
	if not is_inside_tree(): return
	_refreshing = false
	if version != Global.session_version or version != _session: return
	var data: Variant = APIClient.data_of(response)
	_sync_friends(data if response.get("ok", false) and data is Array else [])

func _sync_friends(rows: Array) -> void:
	var online: Dictionary = {}
	for row in rows:
		if not row is Dictionary or not row.get("online", false): continue
		var id := int(row.get("id", 0))
		if id <= 0 or id == Global.player_id: continue
		online[id] = row
	for id in avatars.keys():
		if not online.has(id):
			avatars[id].queue_free()
			avatars.erase(id)
	for id in online:
		var row: Dictionary = online[id]
		var code := str(row.get("character_code", ""))
		if not Global.CHARACTERS.has(code): code = "farmer_female"
		var display_name: Variant = row.get("display_name")
		var title := str(display_name).strip_edges() if display_name is String else ""
		if title.is_empty(): title = str(row.get("username", "Friend"))
		if avatars.has(id):
			var existing: Node2D = avatars[id]
			existing.get_node("FriendName").text = title
			if existing.get_meta("character_code") == code: continue
			_update_character(existing, code)
			continue
		var spot := _random_spot()
		if not spot.is_finite(): continue # Wait for space rather than overlap friends.
		var avatar := Node2D.new()
		avatar.name = "OnlineFriend_%d" % id
		avatar.position = spot
		avatar.z_index = 2
		add_child(avatar)
		avatars[id] = avatar
		var label := preload("res://Scripts/ui/player_namecard.gd").new()
		label.name = "FriendName"
		label.text = title
		label.position.y = -182
		avatar.add_child(label)
		_update_character(avatar, code)

func _update_character(avatar: Node2D, code: String) -> void:
	var old := avatar.get_node_or_null("Character")
	if old != null:
		avatar.remove_child(old)
		old.queue_free()
	var sprite := Preview.new()
	sprite.name = "Character"
	sprite.character = code
	sprite.direction = "front"
	avatar.add_child(sprite)
	var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, 0)
	var bounds := texture.get_image().get_used_rect()
	var factor := 140.0 / maxf(1.0, bounds.size.y)
	sprite.scale = Vector2.ONE * factor
	var ground := 321.0 if not str(Global.CHARACTERS[code].folder).is_empty() else float(bounds.end.y)
	sprite.position.y = -(ground - texture.get_height() * 0.5) * factor
	avatar.set_meta("character_code", code)

func _random_spot() -> Vector2:
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 32.0
	query.shape = circle
	query.collision_mask = 1
	query.collide_with_areas = false
	var player: CharacterBody2D = get_parent().player
	if is_instance_valid(player): query.exclude = [player.get_rid()]
	for attempt in 128:
		var point := Vector2(_rng.randf_range(FLOOR.position.x, FLOOR.end.x), _rng.randf_range(FLOOR.position.y, FLOOR.end.y))
		var occupied := false
		if is_instance_valid(player) and to_global(point).distance_to(player.global_position + Vector2(0, 97) * player.scale.y) < SPACING:
			continue
		for avatar in avatars.values():
			if point.distance_to(avatar.position) < SPACING:
				occupied = true; break
		if occupied: continue
		query.transform = Transform2D(0, to_global(point))
		if get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty(): return point
	return Vector2.INF

func _exit_tree() -> void:
	if Global.session_changed.is_connected(_session_changed): Global.session_changed.disconnect(_session_changed)
	if is_instance_valid(APIClient.realtime):
		APIClient.realtime.standalone_enabled = _previous_standalone
		APIClient.realtime.pause_movement = _previous_pause
