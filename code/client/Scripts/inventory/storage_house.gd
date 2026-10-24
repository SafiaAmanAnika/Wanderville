extends Node2D
# Makes the CDS building clickable: click it -> storage menu (inventory.png) opens.
# Added to the world by character_spawner.gd, so map.tscn didn't need editing.

const BUILDING := "cds"
const MENU_SCRIPT := preload("res://Scripts/inventory/storage_menu.gd")

var _poly: CollisionPolygon2D
var _sprite: Sprite2D
var _menu: Node
var _hovering := false
var _tile_buildings: Array[Dictionary] = []


func _ready() -> void:
	_poly = get_parent().get_node_or_null("Map/CollisionLayer/Collision_cds") as CollisionPolygon2D
	var building := get_parent().find_child(BUILDING, true, false)
	if building:
		_sprite = building.get_node_or_null("Sprite2D") as Sprite2D
	# map2 paints CDS into a TileMapLayer instead of using a named Sprite2D.
	for node in get_parent().find_children("*", "TileMapLayer", true, false):
		var layer := node as TileMapLayer
		if layer.tile_set == null: continue
		for index in layer.tile_set.get_source_count():
			var source_id := layer.tile_set.get_source_id(index)
			var source := layer.tile_set.get_source(source_id) as TileSetAtlasSource
			if source == null or source.texture == null: continue
			if source.texture.resource_path.get_file() != "long_five_arch_hall.png": continue
			if not layer.get_used_cells_by_id(source_id).is_empty():
				_tile_buildings.append({"layer":layer, "source_id":source_id})
	if _poly == null and _sprite == null and _tile_buildings.is_empty():
		push_warning("storage_house: couldn't find the CDS building")


# hand cursor while the mouse is over the building
func _process(_delta: float) -> void:
	var over := _mouse_over_building()
	if over != _hovering:
		_hovering = over
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if over else Input.CURSOR_ARROW)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
			and not is_instance_valid(_menu) and not GameState.menu_open and not GameState.social_open \
			and contains_world_point(get_canvas_transform().affine_inverse() * event.position):
		get_viewport().set_input_as_handled()
		_open_menu()


func _mouse_over_building() -> bool:
	if is_instance_valid(_menu) or GameState.menu_open or GameState.social_open:
		return false
	return contains_world_point(get_global_mouse_position())


func contains_world_point(point: Vector2) -> bool:
	if _poly != null and Geometry2D.is_point_in_polygon(_poly.to_local(point), _poly.polygon):
		return true
	if _sprite != null and _sprite.get_rect().has_point(_sprite.to_local(point)):
		return true
	for building in _tile_buildings:
		var layer: TileMapLayer = building.layer
		if layer.get_cell_source_id(layer.local_to_map(layer.to_local(point))) == building.source_id:
			return true
	return false


func _open_menu() -> void:
	if is_instance_valid(_menu) or GameState.menu_open or GameState.social_open: return
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	_hovering = false
	_menu = MENU_SCRIPT.new()
	_menu.closed.connect(func() -> void: _menu = null)
	get_tree().current_scene.add_child(_menu)
