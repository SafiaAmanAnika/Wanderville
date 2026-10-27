extends Node2D
# Runs the whole housing flow on the map.

const MENU_SCRIPT := preload("res://Scripts/housing/house_menu.gd")
const FLOOR_SCRIPT := preload("res://Scripts/housing/floor_picker.gd")
const EXTERIOR_SCENE := preload("res://Scenes/house_exterior.tscn")
const FURNITURE_MENU := preload("res://Scripts/furniture/furniture_menu.gd")

var exterior: Node = null     # the house on the map
var interior: Node = null     # the inside (far away)
var inside := false

# fading for transition
var _fade: ColorRect

# house placement mode
var _ghost: Sprite2D = null
var _ghost_area: Area2D = null
var _placing_id := 0

# furniture placement mode
var _item_ghost: FurnitureItem = null   # the furniture stuck to your mouse
var _item_name := ""

# rearrange mode (S inside the house)
var _arranging := false
var _grab_position := Vector2.ZERO
var _grab_dir := "front"
var _grab_size := 1.0
var _session := -1
var _scope := ""
var _visiting := false
var _panels: Array[Node] = []

func _ready() -> void:
	_session = Global.session_version
	_scope = GameState.house_context_key()
	_visiting = GameState.read_only
	Global.session_changed.connect(_sync_context)
	GameState.session_updated.connect(func(_data: Dictionary): _sync_context())
	GameState.read_only_changed.connect(func(_value: bool): _sync_context())
	GameState.load_house()
	if GameState.house["stage"] != "none":
		_spawn_exterior.call_deferred()

	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)          # starts see-through
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)


func _can_edit() -> bool:
	return not GameState.read_only and _session == Global.session_version and _scope == GameState.house_context_key()


func _sync_context() -> void:
	if _session==Global.session_version and _scope==GameState.house_context_key() and _visiting==GameState.read_only: return
	HousePrompt.hide_text()
	# Discard scene-local references before loading another account/world's state.
	for panel in _panels:
		if is_instance_valid(panel):
			for event in ["picked","chosen","previewed","confirmed","custom_action","closed","visibility_changed"]:
				if not panel.has_signal(event): continue
				for connection in panel.get_signal_connection_list(event): panel.disconnect(event,connection.callable)
			panel.queue_free()
	if not _panels.is_empty(): GameState.menu_open=false
	_panels.clear()
	if _ghost: _ghost.queue_free()
	if _item_ghost: _item_ghost.queue_free()
	_ghost=null; _ghost_area=null; _item_ghost=null; _arranging=false
	if inside and is_instance_valid(exterior):
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player!=null: player.global_position=exterior.door_position()
	inside=false; APIClient.realtime.pause_movement=false
	if is_instance_valid(exterior): exterior.queue_free()
	if is_instance_valid(interior): interior.queue_free()
	exterior=null; interior=null
	_session=Global.session_version; _scope=GameState.house_context_key()
	_visiting=GameState.read_only
	GameState.load_house()
	if _can_edit() and GameState.house.stage!="none": _spawn_exterior.call_deferred()


func _exit_tree() -> void:
	if _can_edit():
		_cancel_furniture()
		GameState.save_house()
	APIClient.realtime.pause_movement=false
	HousePrompt.hide_text()




# fade to black → do something (teleport) → fade back in; player can't move meanwhile
func _transition(action: Callable) -> void:
	GameState.menu_open = true
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, 0.35)
	await tween.finished
	action.call()
	await get_tree().create_timer(0.15).timeout   # let the camera arrive
	tween = create_tween()
	tween.tween_property(_fade, "color:a", 0.0, 0.35)
	await tween.finished
	GameState.menu_open = false


# ─── Input: J (house menu) and F (furniture) ─────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not _can_edit(): return
	if _ghost:                      # placing the house
		_placement_input(event)
		return
	if _item_ghost:                 # placing furniture
		_furniture_input(event)
		return
	if inside and event.is_action_pressed("furniture") and not GameState.menu_open:
		_open_furniture_menu()
		return
	if inside and event.is_action_pressed("rearrange") and not GameState.menu_open:
		_toggle_arrange()
		return
	if _arranging and event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		_grab_under_mouse()
		return
	if event.is_action_pressed("house_menu"):
		_on_house_key()


# J was pressed. Always puts a message on screen, so it can never fail in silence.
func _on_house_key() -> void:
	if not _can_edit(): return
	if GameState.menu_open:
		HousePrompt.flash("J blocked: a menu is already open.", 3.0)
		return
	if inside:
		HousePrompt.flash("J blocked: you are inside the house.", 3.0)
		return
	if GameState.house["stage"] != "none":
		HousePrompt.flash("You already own a house (stage: %s)." % GameState.house["stage"], 3.0)
		_house_options()
		return
	var zone := get_tree().get_first_node_in_group("house_area")
	if zone and not zone.player_inside:
		HousePrompt.flash("Go to the building site to buy a house.", 3.0)
		return
	var menu = MENU_SCRIPT.new()
	_panels.append(menu)
	menu.picked.connect(_start_placement)
	get_tree().current_scene.add_child(menu)
	HousePrompt.flash("House catalog opened.", 2.0)


func _process(_delta: float) -> void:
	if _ghost:
		_ghost.global_position = (get_global_mouse_position() / 32.0).floor() * 32.0   # snap to grid
		_ghost.modulate = Color(0.6, 1, 0.6, 0.75) if _can_place() else Color(1, 0.5, 0.5, 0.75)
	if _item_ghost:
		_item_ghost.global_position = interior.get_global_mouse_position().snapped(Vector2(16, 16))


# ─── Placing the outer layer ─────────────────────────────────────────

func _start_placement(id: int) -> void:
	if not _can_edit(): return
	_placing_id = id
	_ghost = Sprite2D.new()
	_ghost.texture = HouseCatalog.exterior_texture(id)
	_ghost.scale = Vector2.ONE * HouseCatalog.EXTERIOR_SCALE
	_ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ghost.z_index = 50
	add_child(_ghost)
	# an area the size of the picture, to see if it hits buildings / lakes / borders
	_ghost_area = Area2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = _ghost.texture.get_size()      # Area is a child of the scaled sprite
	shape.shape = rect
	_ghost_area.add_child(shape)
	_ghost.add_child(_ghost_area)
	HousePrompt.show_text("Left click to place your house  ·  Right click to cancel")


func _can_place() -> bool:
	var zone := get_tree().get_first_node_in_group("house_area")
	if zone and not zone.contains(_ghost.global_position):
		return false
	for body in _ghost_area.get_overlapping_bodies():
		if not body.is_in_group("player"):
			return false   # touching a building, lake edge, border…
	return true


func _placement_input(event: InputEvent) -> void:
	if not _can_edit(): return
	if not (event is InputEventMouseButton and event.pressed):
		return
	get_viewport().set_input_as_handled()
	if event.button_index == MOUSE_BUTTON_RIGHT:
		_end_placement()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not _can_place():
		HousePrompt.flash("You can't build here.")
		return
	if not GameState.spend_wood(HouseCatalog.OUTER_COST):
		HousePrompt.flash("You need %d wood to build the outer layer." % HouseCatalog.OUTER_COST)
		_end_placement()
		return
	GameState.house = {"id": _placing_id, "position": _ghost.global_position, "stage": "outer", "floor": "", "furniture": []}
	GameState.save_house()
	_end_placement()
	_spawn_exterior()
	HousePrompt.flash("Outer layer built! Walk to the door first and then press H to build the inside (%d wood)." % HouseCatalog.WALLS_COST, 4.0)


func _end_placement() -> void:
	if _ghost:
		_ghost.queue_free()
	_ghost = null
	_ghost_area = null
	HousePrompt.hide_text()


func _spawn_exterior() -> void:
	if not _can_edit() or GameState.house["stage"]=="none" or is_instance_valid(exterior): return
	exterior = EXTERIOR_SCENE.instantiate()
	get_parent().add_child(exterior)
	exterior.global_position = GameState.house["position"]
	exterior.setup(GameState.house["id"])
	exterior.clicked.connect(_on_exterior_clicked)


# ─── H at the door: walls + going inside ─────────────────────────────

func _on_exterior_clicked() -> void:
	if not _can_edit(): return
	match GameState.house["stage"]:
		"outer":
			if not GameState.spend_wood(HouseCatalog.WALLS_COST):
				HousePrompt.flash("Get %d wood to build the inside of the house." % HouseCatalog.WALLS_COST)
				return
			GameState.house["stage"] = "walls"
			GameState.save_house()
			_enter_house()
		"walls", "done":
			_enter_house()


func _enter_house() -> void:
	if not _can_edit(): return
	if interior == null:
		interior = HouseCatalog.interior_scene(GameState.house["id"]).instantiate()
		get_parent().add_child(interior)
		interior.global_position = HouseCatalog.INTERIOR_POSITION
		interior.exited.connect(_leave_house)
		_load_furniture()
	interior.show_floor(GameState.house["floor"])
	await _transition(func() -> void:
		APIClient.realtime.pause_movement = true
		var player := get_tree().get_first_node_in_group("player") as Node2D
		player.global_position = interior.spawn_position())
	inside = true
	if GameState.house["stage"] == "walls":
		_offer_floor()      # after the fade, so the picker isn't covered
	else:
		HousePrompt.flash("Press F to add furniture  ·  Go to the stairs to exit the house", 4.0)


# ─── Floor ───────────────────────────────────────────────────────────

func _offer_floor() -> void:
	if not _can_edit(): return
	if GameState.wood() < HouseCatalog.FLOOR_COST:
		HousePrompt.flash("Get %d wood to build the floor." % HouseCatalog.FLOOR_COST, 3.5)
		return
	var picker = FLOOR_SCRIPT.new()
	_panels.append(picker)
	picker.previewed.connect(func(f: String) -> void:
		if _can_edit() and is_instance_valid(interior): interior.show_floor(f))   # live preview
	picker.chosen.connect(_on_floor_chosen)
	picker.closed.connect(func() -> void:
		if _can_edit() and is_instance_valid(interior) and GameState.house["stage"] != "done":
			interior.show_floor(""))          # "Later" → remove the preview again
	get_tree().current_scene.add_child(picker)


func _on_floor_chosen(floor_name: String) -> void:
	if not _can_edit(): return
	if not GameState.spend_wood(HouseCatalog.FLOOR_COST):
		interior.show_floor("")
		HousePrompt.flash("Get %d wood to build the floor." % HouseCatalog.FLOOR_COST)
		return
	GameState.house["floor"] = floor_name
	GameState.house["stage"] = "done"
	GameState.save_house()
	interior.show_floor(floor_name)
	HousePrompt.flash("Your house is finished! Press F to add furniture  ·  Go to the stairs to exit", 4.0)


# ─── Furniture ───────────────────────────────────────────────────────

func _open_furniture_menu() -> void:
	if not _can_edit(): return
	if GameState.house["stage"] != "done":
		HousePrompt.flash("Build the floor first.")
		return
	_arranging = false
	_highlight_furniture(false)
	var menu = FURNITURE_MENU.new()
	_panels.append(menu)
	menu.picked.connect(_start_furniture)
	get_tree().current_scene.add_child(menu)

func _start_furniture(item_name: String) -> void:
	if not _can_edit(): return
	_item_name = item_name
	_item_ghost = FurnitureCatalog.make(item_name)
	if _item_ghost == null:
		HousePrompt.flash("That item is missing from the furniture pack.")
		return
	_item_ghost.set_ghost(true)
	interior.add_child(_item_ghost)
	HousePrompt.show_text("Left click to place (%d wood)  ·  R to rotate · I to increase & O to decrease · Right click to cancel" % FurnitureCatalog.cost(item_name))


func _furniture_input(event: InputEvent) -> void:
	if not _can_edit(): return
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:   # rotate
		get_viewport().set_input_as_handled()
		_item_ghost.rotate_next()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_I:   # bigger
		get_viewport().set_input_as_handled()
		_resize_item(0.1)
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_O:   # smaller
		get_viewport().set_input_as_handled()
		_resize_item(-0.1)
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	get_viewport().set_input_as_handled()
	if event.button_index == MOUSE_BUTTON_RIGHT:          # cancel
		_cancel_furniture()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not _on_floor(_item_ghost.global_position):
		HousePrompt.flash("Place it on the floor.")
		return
	if not _arranging:                                     # moving what you own is free
		var cost := FurnitureCatalog.cost(_item_name)
		if not GameState.spend_wood(cost):
			HousePrompt.flash("You need %d wood for this." % cost)
			return
	_item_ghost.set_ghost(false)                           # make it real
	AudioManager.play("furniture")
	if not GameState.house.has("furniture"):
		GameState.house["furniture"] = []
	GameState.house["furniture"].append({"name": _item_name, "x": _item_ghost.position.x, "y": _item_ghost.position.y, "dir": _item_ghost.dir, "size": _item_ghost.size_factor})
	GameState.save_house()
	_item_ghost = null
	if _arranging:
		_highlight_furniture(true)
		HousePrompt.show_text("Rearranging  ·  Click a piece to pick it up  ·  R to rotate  ·  S when done")
	else:
		HousePrompt.flash("Placed!")


func _cancel_furniture() -> void:
	if _item_ghost:
		if _arranging:                 # put it back instead of destroying it
			_item_ghost.position = _grab_position
			_item_ghost.set_dir(_grab_dir)
			_item_ghost.set_size_factor(_grab_size)
			_item_ghost.set_ghost(false)
			if not GameState.house.has("furniture"):
				GameState.house["furniture"] = []
			GameState.house["furniture"].append({"name": _item_name, "x": _grab_position.x, "y": _grab_position.y, "dir": _grab_dir, "size": _grab_size})
			GameState.save_house()
		else:
			_item_ghost.queue_free()
	_item_ghost = null
	HousePrompt.hide_text()
	
# S inside the house: put the whole room into rearrange mode, and back out again
func _toggle_arrange() -> void:
	if not _can_edit(): return
	if GameState.house["stage"] != "done":
		HousePrompt.flash("Build the floor first.")
		return
	_arranging = not _arranging
	_highlight_furniture(_arranging)
	if _arranging:
				HousePrompt.show_text("Rearranging  ·  Click a piece  ·  R rotate  ·  I to increase & O to decrease  ·  S when done")
	else:
		GameState.save_house()
		AudioManager.play("furniture")
		HousePrompt.flash("Arrangement saved.")


# a warm tint on every piece while the room is being rearranged
func _highlight_furniture(on: bool) -> void:
	for child in interior.get_children():
		var piece := child as FurnitureItem
		if piece != null:
			piece.modulate = Color(1.1, 0.456, 0.782, 1.0) if on else Color.WHITE


# picks up whatever the mouse is pointing at
func _grab_under_mouse() -> void:
	if not _can_edit(): return
	var piece := _furniture_under_mouse()
	if piece == null:
		HousePrompt.flash("Nothing there - click directly on a piece.", 2.0)
		return
	_grab_position = piece.position
	_grab_dir = piece.dir
	_grab_size = piece.size_factor
	_item_name = piece.id
	_forget_furniture(piece.id, _grab_position)
	_item_ghost = piece
	_item_ghost.set_ghost(true)


# the topmost piece whose picture the mouse is over, or null
func _furniture_under_mouse() -> FurnitureItem:
	var mouse: Vector2 = interior.get_global_mouse_position()
	var found: FurnitureItem = null
	for child in interior.get_children():
		var piece := child as FurnitureItem
		if piece != null and piece.picture_rect().has_point(mouse):
			found = piece       # later children draw on top, so the last match wins
	return found


# drops the saved record of a piece we just picked up, so dropping it does not duplicate it
func _forget_furniture(id: String, pos: Vector2) -> void:
	var saved: Array = GameState.house.get("furniture", [])
	for i in range(saved.size()):
		var f = saved[i]
		if String(f["name"]) == id and is_equal_approx(float(f["x"]), pos.x) and is_equal_approx(float(f["y"]), pos.y):
			saved.remove_at(i)
			return

# I / O while carrying: bigger or smaller, but never into a wall
func _resize_item(step: float) -> void:
	if not _can_edit(): return
	var before: float = _item_ghost.size_factor
	_item_ghost.set_size_factor(before + step)
	if _hits_wall(_item_ghost):
		_item_ghost.set_size_factor(before)          # undo, it would not fit
		HousePrompt.flash("It won't fit - that would hit the wall.", 2.0)


# true if the piece's box overlaps the house walls at its current size
func _hits_wall(piece: FurnitureItem) -> bool:
	var walls := interior.get_node_or_null("WallCollision")
	if walls == null:
		return false
	var rect: Rect2 = piece.picture_rect()
	var box := RectangleShape2D.new()
	box.size = rect.size
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = box
	query.transform = Transform2D(0.0, rect.get_center())
	query.collide_with_areas = false
	for hit in piece.get_world_2d().direct_space_state.intersect_shape(query, 16):
		if hit["collider"] == walls:
			return true
	return false
# true if there's a floor tile under this point
func _on_floor(pos: Vector2) -> bool:
	var floor_name: String = GameState.house["floor"]
	if floor_name == "":
		return false
	var floor_layer := interior.get_node_or_null(floor_name) as TileMapLayer
	if floor_layer == null:
		return true      # floor isn't a TileMapLayer → allow anywhere
	var cell := floor_layer.local_to_map(floor_layer.to_local(pos))
	return floor_layer.get_cell_source_id(cell) != -1


# puts back everything that was placed before (after a restart)
func _load_furniture() -> void:
	for f in GameState.house.get("furniture", []):
		var piece := FurnitureCatalog.make(f["name"], f.get("dir", "front"))
		if piece == null:
			continue          # item from the old library, not in the new pack
		piece.position = Vector2(f["x"], f["y"])
		interior.add_child(piece)
		piece.set_size_factor(float(f.get("size", 1.0)))


# ─── Leaving ─────────────────────────────────────────────────────────

func _leave_house() -> void:
	if not inside:
		return
	_cancel_furniture()             # must run while _arranging is still true,
	if _arranging:                  # otherwise the carried piece gets deleted
		_arranging = false
		_highlight_furniture(false)
	inside = false
	HousePrompt.hide_text()
	await _transition(func() -> void:
		var player := get_tree().get_first_node_in_group("player") as Node2D
		player.global_position = exterior.door_position()
		APIClient.realtime.pause_movement = false)


# ─── Sell / destroy the house ────────────────────────────────────────

func _sell_price() -> int:
	var price := HouseCatalog.wood_spent(GameState.house["stage"]) * HouseCatalog.SELL_AURA_PER_WOOD
	# later: add the value of the furniture inside here
	return price


# J with a house: Sell / Destroy / Cancel
func _house_options() -> void:
	if not _can_edit(): return
	GameState.menu_open = true   # player stops moving while the box is open
	var box := ConfirmationDialog.new()
	UiSkin.apply_dialog(box)
	_panels.append(box)
	box.title = "Your house"
	box.dialog_text = "What do you want to do with your house?\n\n" \
		+ "Sell: removes the house and everything inside, you get %d Aura.\n" % _sell_price() \
		+ "Destroy: removes the house and everything inside, you get nothing."
	box.ok_button_text = "Destroy the house"
	box.add_button("Sell the house", false, "sell")
	box.confirmed.connect(_destroy_house)                    # OK button = Destroy
	box.custom_action.connect(func(action: StringName) -> void:
		if action == "sell":
			box.hide()
			_sell_house())
	get_tree().current_scene.add_child(box)
	box.popup_centered()
	box.visibility_changed.connect(func() -> void:
		if not box.visible:                               # closed any way: Sell, Destroy, Cancel, X
			GameState.menu_open = false
			box.queue_free())


func _sell_house() -> void:
	if not _can_edit(): return
	var price := _sell_price()
	_clear_house()
	GameState.change_aura_offline(price)   # TEMP: offline Aura (no server sell for houses yet)
	HousePrompt.flash("House sold for %d Aura! Press J to build a new one." % price, 3.0)


func _destroy_house() -> void:
	if not _can_edit(): return
	_clear_house()
	HousePrompt.flash("House destroyed. Press J to build a new one.", 3.0)


# removes the house on the map, the inside and everything in it, and clears the save
func _clear_house() -> void:
	if not _can_edit(): return
	_arranging = false              # the carried piece goes with the house
	_cancel_furniture()
	if exterior:
		exterior.queue_free()
		exterior = null
	if interior:
		interior.queue_free()      # the inside, with all furniture in it
		interior = null
	inside = false
	GameState.house = {"id": 0, "position": Vector2.ZERO, "stage": "none", "floor": "", "furniture": []}
	GameState.save_house()
	APIClient.realtime.pause_movement = false
