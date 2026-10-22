extends StaticBody2D
# A built house standing on the map.
# Walk up to the front door → "Press H to open the door" → H → clicked is emitted.

signal clicked   # now means: the player pressed H at the front door

const DOOR_RANGE := 220.0   # how close (in pixels) to DoorPoint the player must stand

var _near := false


func setup(id: int) -> void:
	$Sprite2D.texture = HouseCatalog.exterior_texture(id)
	scale = Vector2.ONE * HouseCatalog.EXTERIOR_SCALE   # picture, collision and DoorPoint grow together


func door_position() -> Vector2:
	return $DoorPoint.global_position


# show / hide the prompt when the player walks up to or away from the door
func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var near : bool = player != null and not GameState.menu_open \
	and $DoorZone.overlaps_body(player)
	if near == _near:
		return
	_near = near
	if near:
		if GameState.house["stage"] == "outer":
			HousePrompt.show_text("Press H to build the inside (%d wood)" % HouseCatalog.WALLS_COST)
		else:
			HousePrompt.show_text("Press H to open the door")
	else:
		HousePrompt.hide_text()


func _unhandled_input(event: InputEvent) -> void:
	if _near and event.is_action_pressed("door"):
		get_viewport().set_input_as_handled()
		_near = false
		HousePrompt.hide_text()
		clicked.emit()
