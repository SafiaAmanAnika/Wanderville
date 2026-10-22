class_name FurnitureItem
extends Node2D
# One piece of furniture, built in code from furniture_manifest.json.
# Its position = the bottom-centre (feet) of the picture.

# the art is drawn small; show every piece this much bigger
const FURNITURE_SCALE := 1.5

var id := ""
var dir := "front"
var _ghost := false
var _sprite: Sprite2D
var _shape: CollisionShape2D


func setup(item_id: String, facing: String = "front") -> void:
	id = item_id
	scale = Vector2.ONE * FURNITURE_SCALE   # picture and collision grow together
	z_index = int(FurnitureCatalog.info(id).get("z_index", 0))   # rugs = -1
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST     # crisp pixels
	add_child(_sprite)
	var body := StaticBody2D.new()
	body.name = "Blocker"
	_shape = CollisionShape2D.new()
	_shape.shape = RectangleShape2D.new()
	body.add_child(_shape)
	add_child(body)
	set_dir(facing)


func set_dir(facing: String) -> void:
	dir = facing
	var info := FurnitureCatalog.info(id)
	var anchor: Array = info["anchor"]
	_sprite.texture = FurnitureCatalog.texture(id, dir)
	_sprite.offset = -Vector2(anchor[0], anchor[1])     # feet sit on the node's position
	var r = info.get("blockers_by_direction", {}).get(dir)
	if r == null or r.is_empty():                        # rugs, wall + tabletop items
		_shape.disabled = true
		return
	(_shape.shape as RectangleShape2D).size = Vector2(r[0 + 2], r[3])
	_shape.position = Vector2(r[0] + r[2] / 2.0 - anchor[0], r[1] + r[3] / 2.0 - anchor[1])
	_shape.disabled = _ghost


func rotate_next() -> void:
	var i := FurnitureCatalog.DIRS.find(dir)
	set_dir(FurnitureCatalog.DIRS[(i + 1) % 4])


# ghost = see-through and no collision (while you're still moving it)
func set_ghost(on: bool) -> void:
	_ghost = on
	modulate = Color(1, 1, 1, 0.6) if on else Color.WHITE
	set_dir(dir)
