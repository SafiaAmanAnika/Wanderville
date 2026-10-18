extends RefCounted
class_name MovementArena
## A clearly labelled, isolated movement arena for deterministic collision tests.
##
## **This is not the campus.** It exists because the real campus outline is
## concave -- the lakes are C-shaped with walkable notches inside them -- so
## "is this point inside a campus polygon" is not a sound way to prove collision
## works. This arena is a plain box with flat walls, where "the player crossed a
## wall" is unambiguous.
##
## The campus collision is still built and still real (see CampusCollision); the
## campus tests assert that the real world measurably deflects a player, while
## this arena provides the hard geometric guarantee that a boundary was not
## crossed.
##
## Geometry is in absolute coordinates around CampusCollision.CAMPUS_SPAWN, so the
## same deterministic spawn points work in both.

const NAME := "ISOLATED TEST ARENA (not the campus)"

## Sized so the longest scripted run in the suite fits from any spawn-ring
## position. The tests drive up to 5.0s at 300 units/second, which is 1500 units,
## and a player may spawn 260 units off centre in any direction, so the half-size
## must exceed 1760. At 1200 it did not: a 5-second run was quietly wall-limited to
## about 1014 units and a test that expected more reported a movement defect that
## did not exist. The wall-crossing test compensates with a longer run so it still
## reaches the wall.
const WIDTH := 4000.0
const HEIGHT := 4000.0
const WALL := 60.0


static func build(parent: Node) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = "MovementArena"
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)

	var centre := CampusCollision.CAMPUS_SPAWN
	var half_w := WIDTH * 0.5
	var half_h := HEIGHT * 0.5

	# Four solid walls, each a rectangle, drawn so their inner faces sit exactly
	# on the arena bounds. A player at the centre therefore has exactly half_h
	# units of travel north before it must stop.
	_add_rect(body, Vector2(centre.x, centre.y - half_h - WALL * 0.5),
		Vector2(WIDTH + WALL * 2.0, WALL))
	_add_rect(body, Vector2(centre.x, centre.y + half_h + WALL * 0.5),
		Vector2(WIDTH + WALL * 2.0, WALL))
	_add_rect(body, Vector2(centre.x - half_w - WALL * 0.5, centre.y),
		Vector2(WALL, HEIGHT))
	_add_rect(body, Vector2(centre.x + half_w + WALL * 0.5, centre.y),
		Vector2(WALL, HEIGHT))
	# No internal obstacles on purpose.
	#
	# An earlier version had a central block, which made every straight-line
	# distance assertion depend on where the player happened to spawn: from the
	# north of the ring the block was only 160 units away, from the south 680. The
	# outer walls alone are enough to prove collision, and leaving the interior
	# clear is what makes the travel measurements reproducible.
	print("[MovementArena] built: %s, %dx%d walls, interior clear" % [NAME, int(WIDTH), int(HEIGHT)])
	return body


static func _add_rect(body: StaticBody2D, position: Vector2, size: Vector2) -> void:
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	shape.shape = rectangle
	body.add_child(shape)
	shape.position = position


## The northern inner wall face, in absolute coordinates. A player walking north
## from the spawn centre must never pass this.
static func north_wall_y() -> float:
	return CampusCollision.CAMPUS_SPAWN.y - HEIGHT * 0.5


## Distance a player has to walk north before reaching the wall.
static func north_travel_limit() -> float:
	return HEIGHT * 0.5


## Every wall rectangle, so a test can run the same point-in-rectangle check the
## server's physics is enforcing.
static func rectangles() -> Array:
	var centre := CampusCollision.CAMPUS_SPAWN
	var half_w := WIDTH * 0.5
	var half_h := HEIGHT * 0.5
	var rows: Array = []
	rows.append({
		"min_x": centre.x - half_w - WALL, "max_x": centre.x + half_w + WALL,
		"min_y": centre.y - half_h - WALL, "max_y": centre.y - half_h,
	})
	rows.append({
		"min_x": centre.x - half_w - WALL, "max_x": centre.x + half_w + WALL,
		"min_y": centre.y + half_h, "max_y": centre.y + half_h + WALL,
	})
	rows.append({
		"min_x": centre.x - half_w - WALL, "max_x": centre.x - half_w,
		"min_y": centre.y - half_h, "max_y": centre.y + half_h,
	})
	rows.append({
		"min_x": centre.x + half_w, "max_x": centre.x + half_w + WALL,
		"min_y": centre.y - half_h, "max_y": centre.y + half_h,
	})
	return rows


static func inside_any_wall(x: float, y: float) -> bool:
	for row in rectangles():
		if (x >= float(row["min_x"]) and x <= float(row["max_x"])
				and y >= float(row["min_y"]) and y <= float(row["max_y"])):
			return true
	return false


## Write the arena's rectangles for offline inspection by tests.
##
## Deliberately never touches ``map.tscn``: serialising the campus here is what
## made every arena process pay ~15 seconds and flood its log with TileSet errors.
static func dump(path: String) -> bool:
	if path == "":
		return false
	var rows: Array = []
	for row in rectangles():
		var min_x := float(row["min_x"])
		var max_x := float(row["max_x"])
		var min_y := float(row["min_y"])
		var max_y := float(row["max_y"])
		rows.append({"kind": "rectangle", "radius": 0.0, "points": [
			[min_x, min_y], [max_x, min_y], [max_x, max_y], [min_x, max_y],
		]})
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({
		"spawn": [CampusCollision.CAMPUS_SPAWN.x, CampusCollision.CAMPUS_SPAWN.y],
		"arena": true,
		"name": NAME,
		"width": WIDTH,
		"height": HEIGHT,
		"shapes": rows,
	}))
	file.close()
	return true