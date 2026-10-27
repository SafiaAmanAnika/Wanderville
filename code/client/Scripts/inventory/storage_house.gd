extends Node2D
# Makes the CDS building clickable: click it -> storage menu (inventory.png) opens.
# Added to the world by character_spawner.gd, so map.tscn didn't need editing.

const BUILDING := "cds"
const MENU_SCRIPT := preload("res://Scripts/inventory/storage_menu.gd")

var _poly: CollisionPolygon2D
var _menu: Node
var _hovering := false


func _ready() -> void:
	_poly = get_parent().get_node_or_null("Map/CollisionLayer/Collision_cds") as CollisionPolygon2D
	if _poly == null:
		push_warning("storage_house: couldn't find Collision_cds")

# hand cursor while the mouse is over the building
func _process(_delta: float) -> void:
	var over := _mouse_over_building()
	if over != _hovering:
		_hovering = over
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if over else Input.CURSOR_ARROW)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
			and _mouse_over_building():
		get_viewport().set_input_as_handled()
		_open_menu()


func _mouse_over_building() -> bool:
	if _poly == null or _menu != null or GameState.menu_open or GameState.social_open:
		return false
	return Geometry2D.is_point_in_polygon(_poly.to_local(get_global_mouse_position()), _poly.polygon)

func _open_menu() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	_hovering = false
	_menu = MENU_SCRIPT.new()
	_menu.mode = "storage"   
	_menu.closed.connect(func() -> void: _menu = null)
	get_tree().current_scene.add_child(_menu)
