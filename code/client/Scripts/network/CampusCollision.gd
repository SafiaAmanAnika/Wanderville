extends RefCounted
class_name CampusCollision
## Builds the headless server's collision world from the **existing** campus map.
##
## The dedicated server cannot simply run ``Scenes/world.tscn``: that scene drags
## in the HUD, FarmController, DayNight, WeatherManager's GPU particles, a
## WaterSource prompt layer and the autoloads, none of which a headless simulation
## needs and some of which would start HTTP and WebSocket clients on a server that
## is supposed to have no network presence of its own.
##
## So the geometry is lifted out of ``Scenes/map.tscn`` instead, which is the
## actual collision resource the game uses. Nothing is redrawn and no wall is
## moved: the polygon points below are read from the map scene itself, so the
## server collides against exactly the lakes, borders and buildings the player
## sees.
##
## The map is instantiated **outside** the scene tree and never added to it. That
## matters: no ``_ready`` runs, so no gameplay script, prompt or autoload side
## effect can fire while harvesting the shapes.
##
## Known gap, stated rather than hidden: the TileMapLayer-backed collision (trees
## and other decor drawn from the TileSet) is **not** reproduced here. Those tiles
## carry their collision inside the TileSet's atlas data, which is a different
## mechanism from the declarative polygons harvested below. Campus borders, lake
## edges and every building *are* reproduced.

const MAP_SCENE := "res://Scenes/map.tscn"

## Where the production campus places the player, read from world.tscn. Used as
## the centre of the movement area so tests exercise the real walkable region
## rather than an empty corner of the map.
const CAMPUS_SPAWN := Vector2(7378, -891)

const PADDING := 2048.0


class ExtractedShape:
	var transform: Transform2D
	var kind: String  # "polygon" or "rectangle" or "circle"
	var polygon := PackedVector2Array()
	var size := Vector2.ZERO
	var radius := 0.0


## Harvest every collision shape the map declares. Returns [] if the map is
## missing, so the caller can fail loudly rather than simulating in a void.
##
## Cached. Instantiating map.tscn builds its TileSets, which is expensive and
## noisy, and this is called both to build the physics world and to dump the
## outline for tests. Doing it once keeps startup affordable.
static var _cached: Array = []
static var _loaded := false


static func extract_shapes() -> Array:
	if _loaded:
		return _cached
	_loaded = true
	_cached = []
	if not ResourceLoader.exists(MAP_SCENE):
		push_error("[CampusCollision] " + MAP_SCENE + " is missing")
		return _cached
	var packed: PackedScene = load(MAP_SCENE)
	if packed == null:
		push_error("[CampusCollision] could not load " + MAP_SCENE)
		return _cached
	var instance := packed.instantiate()
	if instance == null:
		push_error("[CampusCollision] could not instantiate " + MAP_SCENE)
		return _cached
	# Walk with an explicit transform accumulator rather than global_transform,
	# because these nodes are deliberately not in a tree.
	_walk(instance, Transform2D.IDENTITY, _cached)
	instance.free()
	return _cached


static func _walk(node: Node, accumulated: Transform2D, out: Array) -> void:
	# Only 2D nodes carry a transform. map.tscn also contains Panels, Labels and
	# Timers, which have none, so this cannot assume Node2D.
	var here := accumulated
	if node is Node2D:
		here = accumulated * (node as Node2D).transform
	if node is StaticBody2D:
		for child in node.get_children():
			_collect_shape(child, here * (child as Node2D).transform, out)
	for child in node.get_children():
		_walk(child, here, out)


static func _collect_shape(node: Node, transform: Transform2D, out: Array) -> void:
	if node is CollisionPolygon2D:
		var shape := ExtractedShape.new()
		shape.transform = transform
		shape.kind = "polygon"
		shape.polygon = (node as CollisionPolygon2D).polygon
		if shape.polygon.size() >= 3:
			out.append(shape)
		return
	if node is CollisionShape2D:
		var holder := node as CollisionShape2D
		if holder.shape is RectangleShape2D:
			var shape := ExtractedShape.new()
			shape.transform = transform
			shape.kind = "rectangle"
			shape.size = (holder.shape as RectangleShape2D).size
			out.append(shape)
		elif holder.shape is CircleShape2D:
			var shape := ExtractedShape.new()
			shape.transform = transform
			shape.kind = "circle"
			shape.radius = (holder.shape as CircleShape2D).radius
			out.append(shape)


## Create the collision world as a single StaticBody2D.
##
## One body with many shapes rather than many bodies: the shapes are static, so
## they all share one broadphase entry and the physics server does far less work
## than it would with a body per wall.
static func build(parent: Node) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = "CampusCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	# Deliberately NOT set to PROCESS_MODE_DISABLED. That looks like a way to
	# stop a static body doing work, but it also removes the node from the
	# physics space, so the campus silently stopped colliding with anything. A
	# StaticBody2D has no per-frame work to suppress in the first place.
	parent.add_child(body)

	for entry in extract_shapes():
		match entry.kind:
			"polygon":
				var polygon := CollisionPolygon2D.new()
				polygon.polygon = entry.polygon
				body.add_child(polygon)
				polygon.transform = entry.transform
			"rectangle":
				var rectangle := CollisionShape2D.new()
				var box := RectangleShape2D.new()
				box.size = entry.size
				rectangle.shape = box
				body.add_child(rectangle)
				rectangle.transform = entry.transform
			"circle":
				var circle := CollisionShape2D.new()
				var disc := CircleShape2D.new()
				disc.radius = entry.radius
				circle.shape = disc
				body.add_child(circle)
				circle.transform = entry.transform
	return body


## Count of harvested shapes, for the server's startup log and for tests that
## assert the collision world was actually populated rather than silently empty.
static func shape_count() -> int:
	return extract_shapes().size()


## Write the harvested polygons as JSON.
##
## Tests use this to run the *same* geometry through a point-in-polygon check, so
## "the player did not pass through the lake" is verified against the real campus
## outline rather than against a hand-copied guess at where the lake is.
static func dump(path: String) -> int:
	if path == "":
		return 0
	var shapes := extract_shapes()
	var rows: Array = []
	for entry in shapes:
		var points: Array = []
		if entry.kind == "polygon":
			for point in entry.polygon:
				var world: Vector2 = entry.transform * point
				points.append([world.x, world.y])
		elif entry.kind == "rectangle":
			var half: Vector2 = entry.size * 0.5
			for corner in [
				Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
				Vector2(half.x, half.y), Vector2(-half.x, half.y),
			]:
				var world: Vector2 = entry.transform * corner
				points.append([world.x, world.y])
		elif entry.kind == "circle":
			var centre: Vector2 = entry.transform * Vector2.ZERO
			points.append([centre.x, centre.y])
		rows.append({"kind": entry.kind, "radius": entry.radius, "points": points})
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return 0
	file.store_string(JSON.stringify({"spawn": [CAMPUS_SPAWN.x, CAMPUS_SPAWN.y], "shapes": rows}))
	file.close()
	return shapes.size()