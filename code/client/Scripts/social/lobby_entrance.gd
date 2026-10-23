extends Node2D
# Click audi for the Social Lobby, or library for Character Customization.
# The shared SceneManager fade covers the swap, so there is no local overlay.
# Added to the world by character_spawner.gd, so map.tscn didn't need editing.

const BUILDING := "audi"
const DESTINATIONS := {"audi": "social", "library": "customization"}
const TILE_DESTINATIONS := {
	"left_three_arch_hall.png": "social",
	"right_four_arch_hall.png": "customization",
}

var _sprite: Sprite2D
var _sprites: Dictionary = {}
var _destination := ""
var _hovering := false
var _entering := false
var _tile_buildings: Array[Dictionary] = []


func _ready() -> void:
	for id in DESTINATIONS:
		var building := get_parent().find_child(id, true, false)
		var sprite := building.get_node_or_null("Sprite2D") as Sprite2D if building else null
		if sprite != null:
			_sprites[id] = sprite
		else:
			pass # The new campus uses painted TileMapLayer buildings instead.
	_sprite = _sprites.get(BUILDING)
	for node in get_parent().find_children("*", "TileMapLayer", true, false):
		var layer := node as TileMapLayer
		if layer.tile_set == null: continue
		for index in layer.tile_set.get_source_count():
			var source_id := layer.tile_set.get_source_id(index)
			var source := layer.tile_set.get_source(source_id) as TileSetAtlasSource
			if source == null or source.texture == null: continue
			var destination: String = TILE_DESTINATIONS.get(source.texture.resource_path.get_file(), "")
			if destination.is_empty(): continue
			var cells := layer.get_used_cells_by_id(source_id)
			if not cells.is_empty():
				_tile_buildings.append({"layer":layer, "source_id":source_id, "destination":destination})


func _exit_tree() -> void:
	# The world scene is freed during the shared fade, so the input lock is
	# released here instead of after the (never-reached) fade-back.
	GameState.menu_open = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


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
		_enter_lobby()


func _mouse_over_building() -> bool:
	_destination = ""
	if _entering or GameState.menu_open or GameState.social_open:
		return false
	for id in _sprites:
		var sprite: Sprite2D = _sprites[id]
		if sprite.get_rect().has_point(sprite.to_local(get_global_mouse_position())):
			_destination = DESTINATIONS[id]
			return true
	_destination = destination_at(get_global_mouse_position())
	return not _destination.is_empty()


func destination_at(world_position: Vector2) -> String:
	# Query the actual painted cell, including transformed/mirrored building tiles.
	# No duplicate TileMap or guessed screen-space rectangles are needed.
	for building in _tile_buildings:
		var layer: TileMapLayer = building.layer
		var cell := layer.local_to_map(layer.to_local(world_position))
		if layer.get_cell_source_id(cell) == building.source_id:
			return building.destination
	return ""


func _enter_lobby() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	_hovering = false
	_entering = true
	GameState.menu_open = true
	if _destination == "customization":
		SceneManager.goto_character_customization(true)
	else:
		SceneManager.goto_social_lobby()
