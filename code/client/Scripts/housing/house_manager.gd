extends Node2D
# Runs the whole housing flow on the map.

#fading for transition 
var _fade: ColorRect 

const MENU_SCRIPT := preload("res://Scripts/housing/house_menu.gd")
const FLOOR_SCRIPT := preload("res://Scripts/housing/floor_picker.gd")
const EXTERIOR_SCENE := preload("res://Scenes/house_exterior.tscn")

var exterior: Node = null     # the house on the map
var interior: Node = null     # the inside (far away)
var inside := false

# placement mode
var _ghost: Sprite2D = null
var _ghost_area: Area2D = null
var _placing_id := 0


func _ready() -> void:
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

# ─── J: house menu ───────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if _ghost:
		_placement_input(event)
		return
	if event.is_action_pressed("house_menu") and not GameState.menu_open and not inside:
		if GameState.house["stage"] != "none":
			_house_options()
			return
		var menu = MENU_SCRIPT.new()
		menu.picked.connect(_start_placement)
		get_tree().current_scene.add_child(menu)


# ─── Placing the outer layer ─────────────────────────────────────────

func _start_placement(id: int) -> void:
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


func _process(_delta: float) -> void:
	if _ghost:
		_ghost.global_position = (get_global_mouse_position() / 32.0).floor() * 32.0   # snap to grid
		_ghost.modulate = Color(0.6, 1, 0.6, 0.75) if _can_place() else Color(1, 0.5, 0.5, 0.75)


func _can_place() -> bool:
	for body in _ghost_area.get_overlapping_bodies():
		if not body.is_in_group("player"):
			return false   # touching a building, lake edge, border…
	return true


func _placement_input(event: InputEvent) -> void:
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
	GameState.house = {"id": _placing_id, "position": _ghost.global_position, "stage": "outer", "floor": ""}
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
	exterior = EXTERIOR_SCENE.instantiate()
	get_parent().add_child(exterior)
	exterior.global_position = GameState.house["position"]
	exterior.setup(GameState.house["id"])
	exterior.clicked.connect(_on_exterior_clicked)


# ─── Clicking the house: walls + going inside ────────────────────────

func _on_exterior_clicked() -> void:
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
	if interior == null:
		interior = HouseCatalog.interior_scene(GameState.house["id"]).instantiate()
		get_parent().add_child(interior)
		interior.global_position = HouseCatalog.INTERIOR_POSITION
		interior.exited.connect(_leave_house)
	interior.show_floor(GameState.house["floor"])
	await _transition(func() -> void:
		APIClient.realtime.pause_movement = true
		var player := get_tree().get_first_node_in_group("player") as Node2D
		player.global_position = interior.spawn_position())
	inside = true
	if GameState.house["stage"] == "walls":
		_offer_floor()      # after the fade, so the picker isn't covered


# ─── Floor ───────────────────────────────────────────────────────────

func _offer_floor() -> void:
	if GameState.wood() < HouseCatalog.FLOOR_COST:
		HousePrompt.flash("Get %d wood to build the floor." % HouseCatalog.FLOOR_COST, 3.5)
		return
	var picker = FLOOR_SCRIPT.new()
	picker.previewed.connect(func(f: String) -> void: interior.show_floor(f))   # live preview
	picker.chosen.connect(_on_floor_chosen)
	picker.closed.connect(func() -> void:
		if GameState.house["stage"] != "done":
			interior.show_floor(""))          # "Later" → remove the preview again
	get_tree().current_scene.add_child(picker)


func _on_floor_chosen(floor_name: String) -> void:
	if not GameState.spend_wood(HouseCatalog.FLOOR_COST):
		interior.show_floor("")
		HousePrompt.flash("Get %d wood to build the floor." % HouseCatalog.FLOOR_COST)
		return
	GameState.house["floor"] = floor_name
	GameState.house["stage"] = "done"
	GameState.save_house()
	interior.show_floor(floor_name)
	HousePrompt.flash("Your house is finished! Go to the stairs to exit the house", 4.0)
# ─── Leaving ─────────────────────────────────────────────────────────

func _leave_house() -> void:
	if not inside:
		return
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
	GameState.menu_open = true   # player stops moving while the box is open
	var box := ConfirmationDialog.new()
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
	box.visibility_changed.connect(func() -> void:
		if not box.visible:                               # closed any way: Sell, Destroy, Cancel, X
			GameState.menu_open = false
			box.queue_free())
	get_tree().current_scene.add_child(box)
	box.popup_centered()


func _sell_house() -> void:
	var price := _sell_price()
	_clear_house()
	GameState.change_aura_offline(price)   # TEMP: offline Aura (no server sell for houses yet)
	HousePrompt.flash("House sold for %d Aura! Press J to build a new one." % price, 3.0)


func _destroy_house() -> void:
	_clear_house()
	HousePrompt.flash("House destroyed. Press J to build a new one.", 3.0)


# removes the house on the map, the inside and everything in it, and clears the save
func _clear_house() -> void:
	if exterior:
		exterior.queue_free()
		exterior = null
	if interior:
		interior.queue_free()      # the inside, with everything placed in it
		interior = null
	inside = false
	GameState.house = {"id": 0, "position": Vector2.ZERO, "stage": "none", "floor": ""}
	GameState.save_house()
	APIClient.realtime.pause_movement = false
