extends Node2D

var _poly: CollisionPolygon2D

func _ready() -> void:
	_poly = get_parent().get_node_or_null("Map/CollisionLayer/Collision_cafe") as CollisionPolygon2D

func _unhandled_input(event: InputEvent) -> void:
	if _poly == null or GameState.menu_open:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Geometry2D.is_point_in_polygon(_poly.to_local(get_global_mouse_position()), _poly.polygon):
			get_viewport().set_input_as_handled()
			SceneManager.goto_marketplace()
