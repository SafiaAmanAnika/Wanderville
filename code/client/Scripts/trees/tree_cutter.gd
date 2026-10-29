extends Node
## Cut seasonal trees for wood with C (the "cut_trees" action).
##
## Lives under the map's Trees node (TreeSeasonManager adds it). Every player
## has their own forest: the server remembers which map trees this player cut
## and which trees it grew for them after they cleared a season (GET /trees),
## and it decides every chop (POST /trees/chop) from the player's position, the
## season and the tree, so wood can never be granted by the client. Palm trees
## are scenery and cannot be cut.
##
## Distances are measured from the trunk, which geometry.json exports for every
## map tree: 18 node units below a tree's origin (a 128x160 sprite at 0.25,
## centred, meets the ground 72px below its middle).

const CampusLayout := preload("res://Scripts/network/CampusLayout.gd")
const WOOD_TEXTURE := preload("res://Assests_2/Trees/wood.png")
const SEASON_GROUPS := ["Summer", "Autumn", "Winter", "Spring"]
const TRUNK := Vector2(0, 18)
const FLOAT_SECONDS := 3.0
const WOOD_SCALE := 0.3
const OFFLINE_REGROW := 12

var _trees: Node2D                 ## the map's Trees node
var _wood_per_tree := 15
var _reach := 220.0
var _busy := false
var _prompt := ""
var _offline_cut := {}             ## tree_id -> true, when nobody is signed in
var _session := -1


func _ready() -> void:
	_trees = get_parent() as Node2D
	_reach = float(CampusLayout.data.get("tree_reach", _reach))
	Global.session_changed.connect(_load_forest)
	GameState.read_only_changed.connect(func(_value: bool) -> void: _load_forest())
	_load_forest.call_deferred()


# ── forest state ─────────────────────────────────────────────────────

func _load_forest() -> void:
	_session = Global.session_version
	var session := _session
	_reset_forest()
	if not Global.is_logged_in() or GameState.read_only:
		return
	var response: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_GET, "/trees")
	if session != Global.session_version or not is_inside_tree():
		return
	if not response.get("ok", false):
		push_warning("Trees: could not load your forest - " + APIClient.error_text(response))
		return
	var data: Dictionary = APIClient.data_of(response)
	_wood_per_tree = int(data.get("wood_per_tree", _wood_per_tree))
	_reach = float(data.get("reach", _reach))
	for tree_id in data.get("cut", []):
		var tree := _map_tree(str(tree_id))
		if tree != null:
			tree.visible = false
	for row in data.get("spawned", []):
		_grow(row)


## Every map tree standing again and every grown tree gone, ready for a reload.
func _reset_forest() -> void:
	_offline_cut.clear()
	for group_name in SEASON_GROUPS:
		var group := _trees.get_node_or_null(group_name)
		if group == null:
			continue
		for tree in group.get_children():
			if tree.has_meta("grown"):
				tree.queue_free()
			else:
				tree.visible = true


func _map_tree(tree_id: String) -> Node2D:
	return _trees.get_node_or_null(tree_id) as Node2D


## Place a tree the server grew; its x/y is where the trunk meets the ground.
func _grow(row: Dictionary) -> void:
	var group := _trees.get_node_or_null(str(row["season"]).capitalize())
	var packed := load(str(row["scene"])) as PackedScene
	if group == null or packed == null:
		return
	var tree := packed.instantiate() as Node2D
	tree.set_meta("grown", true)
	tree.set_meta("tree_id", str(row["id"]))
	group.add_child(tree)
	tree.global_position = Vector2(float(row["x"]), float(row["y"])) - tree.global_transform.basis_xform(TRUNK)


func _tree_id(tree: Node2D) -> String:
	if tree.has_meta("tree_id"):
		return str(tree.get_meta("tree_id"))
	return tree.get_parent().name + "/" + tree.name


func _trunk(tree: Node2D) -> Vector2:
	return tree.global_transform * TRUNK


# ── walking up to a tree ─────────────────────────────────────────────

func _player() -> Node2D:
	for body in get_tree().get_nodes_in_group("player"):
		if body is Node2D and body.get("use_saved_appearance") != false:
			return body
	return null


## The current season's group is the one TreeSeasonManager made visible.
func _season_group() -> Node2D:
	for group_name in SEASON_GROUPS:
		var group := _trees.get_node_or_null(group_name) as Node2D
		if group != null and group.visible:
			return group
	return null


func _nearest_tree() -> Node2D:
	var player := _player()
	var group := _season_group()
	if player == null or group == null:
		return null
	var best: Node2D = null
	var best_distance := _reach
	for tree in group.get_children():
		if not tree is Node2D or not tree.visible or tree.is_queued_for_deletion():
			continue
		# Same point and distance the server measures on a chop.
		var distance: float = player.global_position.distance_to(_trunk(tree))
		if distance <= best_distance:
			best_distance = distance
			best = tree
	return best


func _process(_delta: float) -> void:
	if GameState.read_only or GameState.menu_open or GameState.social_open or _busy:
		_set_prompt("")
		return
	_set_prompt("Press C to cut the tree" if _nearest_tree() != null else "")


func _set_prompt(text: String) -> void:
	if text == _prompt:
		return
	_prompt = text
	if text == "":
		HousePrompt.hide_text()
	else:
		HousePrompt.show_text(text)


func _unhandled_input(event: InputEvent) -> void:
	if not InputMap.has_action("cut_trees") or not event.is_action_pressed("cut_trees") or event.is_echo():
		return
	if _busy or GameState.read_only or GameState.menu_open or GameState.social_open:
		return
	var tree := _nearest_tree()
	if tree == null:
		return
	get_viewport().set_input_as_handled()
	_cut(tree)


# ── cutting ──────────────────────────────────────────────────────────

func _cut(tree: Node2D) -> void:
	_busy = true
	_set_prompt("")
	var player := _player()
	if player != null and player.has_method("play_action"):
		player.play_action("axe")
	var sound := _start_chop_sound()
	var session := Global.session_version
	var grown: Array = []
	if Global.is_logged_in():
		var avoid: Array = []
		if str(GameState.house.get("stage", "none")) != "none":
			var spot: Vector2 = GameState.house["position"]
			avoid.append([spot.x, spot.y])
		var response: Dictionary = await APIClient.authenticated(HTTPClient.METHOD_POST,
				"/trees/chop", {"tree_id": _tree_id(tree), "avoid": avoid})
		if session != Global.session_version or not is_inside_tree():
			return
		if not response.get("ok", false):
			_stop_chop_sound(sound)
			# Keep the standing prompt from replacing this error on the next frame.
			await HousePrompt.flash(APIClient.error_text(response), 3.0)
			_busy = false
			return
		grown = APIClient.data_of(response).get("spawned", [])
	else:
		_offline_cut[_tree_id(tree)] = true
	var trunk := _trunk(tree)
	if tree.has_meta("grown"):
		tree.queue_free()
	else:
		tree.visible = false
	await _float_wood(trunk)
	if session != Global.session_version or not is_inside_tree():
		return
	if Global.is_logged_in():
		await GameState.refresh_gameplay()   # the server already stored the wood
	else:
		GameState.add_item_offline("wood", "Wood", _wood_per_tree, "tools", "material")
		if _nearest_count() == 0:
			grown = _offline_regrow()
	for row in grown:
		_grow(row)
	if grown.is_empty():
		HousePrompt.flash("+%d Wood" % _wood_per_tree, 2.0, false)
	else:
		HousePrompt.flash("+%d Wood  ·  New trees have grown on your map" % _wood_per_tree, 3.0, false)
	_busy = false


## AudioManager caps "cut_wood" at 3 s (SFX_MAX_DURATION); a refused chop
## stops it at once.
func _start_chop_sound() -> AudioStreamPlayer:
	return AudioManager.play("cut_wood")


func _stop_chop_sound(sound: AudioStreamPlayer) -> void:
	# The voice is pooled: stop it only while it is still playing the chop.
	if is_instance_valid(sound) and sound.playing and sound.stream == AudioManager._resolve("cut_wood"):
		sound.stop()


## The wood bobs where the tree stood, then drops into the bag.
func _float_wood(at: Vector2) -> void:
	var piece := Sprite2D.new()
	piece.texture = WOOD_TEXTURE
	piece.z_as_relative = false
	piece.z_index = 50
	# In the world scene, not under the 15x-scaled Map: about a quarter of a
	# tree's 480-unit width.
	get_tree().current_scene.add_child(piece)
	piece.global_scale = Vector2(WOOD_SCALE, WOOD_SCALE)
	piece.global_position = at - Vector2(0, 160)
	var bob := piece.create_tween().set_loops()
	bob.tween_property(piece, "position:y", piece.position.y - 24, 0.5).set_trans(Tween.TRANS_SINE)
	bob.tween_property(piece, "position:y", piece.position.y, 0.5).set_trans(Tween.TRANS_SINE)
	await get_tree().create_timer(FLOAT_SECONDS).timeout
	bob.kill()
	if not is_instance_valid(piece):
		return
	var player := _player()
	var into := piece.create_tween().set_parallel()
	if player != null:
		into.tween_property(piece, "global_position", player.global_position, 0.35)
	into.tween_property(piece, "scale", piece.scale * 0.2, 0.35)
	into.tween_property(piece, "modulate:a", 0.0, 0.35)
	await into.finished
	piece.queue_free()


# ── offline play ─────────────────────────────────────────────────────

func _nearest_count() -> int:
	var group := _season_group()
	if group == null:
		return 0
	var standing := 0
	for tree in group.get_children():
		if tree is Node2D and tree.visible and not tree.is_queued_for_deletion():
			standing += 1
	return standing


## The server's regrow rule, for a game nobody is signed in to.
func _offline_regrow() -> Array:
	var group := _season_group()
	if group == null:
		return []
	var season := group.name.to_lower()
	var scenes: Array = []
	for tree in CampusLayout.data.get("trees", []):
		if tree["season"] == season and not scenes.has(tree["scene"]):
			scenes.append(tree["scene"])
	var xs: Array = []
	var ys: Array = []
	for point in CampusLayout.data.boundary:
		xs.append(float(point[0]))
		ys.append(float(point[1]))
	var farm: Array = CampusLayout.data.get("farm", [[0, 0], [0, 0]])
	var placed: Array = []
	for attempt in 4000:
		if placed.size() == OFFLINE_REGROW or scenes.is_empty():
			break
		var spot := Vector2(randf_range(xs.min(), xs.max()), randf_range(ys.min(), ys.max()))
		if CampusLayout.at_water(spot):
			continue
		var open := true
		for offset in [Vector2.ZERO, Vector2(-150, 0), Vector2(150, 0), Vector2(0, -200), Vector2(0, 60)]:
			if not CampusLayout.walkable(spot + offset):
				open = false
		if not open:
			continue
		if spot.x >= float(farm[0][0]) - 150 and spot.x <= float(farm[1][0]) + 150 \
				and spot.y >= float(farm[0][1]) - 150 and spot.y <= float(farm[1][1]) + 150:
			continue
		var crowded := false
		for other in placed:
			if spot.distance_to(Vector2(other["x"], other["y"])) < 260:
				crowded = true
		if crowded:
			continue
		placed.append({"id": "offline-%d" % attempt, "season": season,
				"scene": scenes.pick_random(), "x": spot.x, "y": spot.y})
	return placed
