extends Node
## A shared, clearance-aware campus grid. Physics still decides actual movement.
const Layout := preload("res://Scripts/network/CampusLayout.gd")
const CELL := 64.0
const RADIUS := 20.0
var grid := AStarGrid2D.new()
var ready_for_paths := false
var boundary := PackedVector2Array()
var obstacles: Array[PackedVector2Array] = []
var temporary_blocks: Dictionary = {}

func _ready() -> void:
	build.call_deferred()

func build() -> void:
	boundary = Layout.polygon(Layout.data.boundary)
	for row in Layout.data.collision: obstacles.append(Layout.polygon(row.points))
	var bounds := Rect2(boundary[0], Vector2.ZERO)
	for point in boundary: bounds = bounds.expand(point)
	var first := cell_of(bounds.position)
	var last := cell_of(bounds.end)
	grid.region = Rect2i(first, last-first+Vector2i.ONE)
	grid.cell_size = Vector2.ONE * CELL
	grid.offset = Vector2.ONE * CELL * 0.5
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	var count := 0
	for y in range(first.y,last.y+1):
		for x in range(first.x,last.x+1):
			var id := Vector2i(x,y)
			grid.set_point_solid(id,not clear(center_of(id)))
			count += 1
			if count % 160 == 0:
				await get_tree().process_frame
				if not is_inside_tree(): return
	ready_for_paths = true

func point_clear(point: Vector2) -> bool:
	if not Geometry2D.is_point_in_polygon(point,boundary): return false
	for polygon in obstacles:
		if Geometry2D.is_point_in_polygon(point,polygon): return false
	return true

func clear(point: Vector2) -> bool:
	for offset in [Vector2.ZERO,Vector2(RADIUS,0),Vector2(-RADIUS,0),Vector2(0,RADIUS),Vector2(0,-RADIUS)]:
		if not point_clear(point+offset): return false
	return true

func cell_of(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x/CELL),floori(point.y/CELL))

func center_of(id: Vector2i) -> Vector2:
	return (Vector2(id)+Vector2.ONE*0.5)*CELL

func usable(id: Vector2i) -> bool:
	return grid.is_in_boundsv(id) and not grid.is_point_solid(id)

func nearest(point: Vector2) -> Vector2:
	var origin := cell_of(point)
	var best := Vector2.INF
	var distance := INF
	for radius in range(5):
		for y in range(-radius,radius+1):
			for x in range(-radius,radius+1):
				var id := origin+Vector2i(x,y)
				if usable(id) and center_of(id).distance_squared_to(point)<distance:
					best=center_of(id); distance=best.distance_squared_to(point)
		if best.is_finite(): return best
	return best

func path(from: Vector2, to: Vector2) -> PackedVector2Array:
	if not ready_for_paths: return PackedVector2Array()
	var start := nearest(from)
	var finish := nearest(to)
	if not start.is_finite() or not finish.is_finite(): return PackedVector2Array()
	return grid.get_point_path(cell_of(start),cell_of(finish))

func mark_blocked(point: Vector2) -> void:
	var id := cell_of(point)
	if not grid.is_in_boundsv(id) or not clear(center_of(id)): return
	grid.set_point_solid(id,true)
	temporary_blocks[id] = Time.get_ticks_msec()+8000

func block_shape(shape_node: Node2D) -> void:
	var local_bounds := Rect2()
	if shape_node is CollisionShape2D and shape_node.shape!=null:
		local_bounds=shape_node.shape.get_rect()
	elif shape_node is CollisionPolygon2D and not shape_node.polygon.is_empty():
		local_bounds=Rect2(shape_node.polygon[0],Vector2.ZERO)
		for point in shape_node.polygon: local_bounds=local_bounds.expand(point)
	else: return
	var bounds := Rect2(shape_node.to_global(local_bounds.position),Vector2.ZERO)
	for corner in [local_bounds.end,Vector2(local_bounds.position.x,local_bounds.end.y),Vector2(local_bounds.end.x,local_bounds.position.y)]:
		bounds=bounds.expand(shape_node.to_global(corner))
	# Large campus polygons are already baked. Never block an entire courtyard
	# because its surrounding border is one concave collision polygon.
	if bounds.get_area()>CELL*CELL*32: return
	bounds=bounds.grow(RADIUS+CELL*0.5)
	var first := cell_of(bounds.position); var last := cell_of(bounds.end)
	for y in range(first.y,last.y+1):
		for x in range(first.x,last.x+1): mark_blocked(center_of(Vector2i(x,y)))

func _process(_delta: float) -> void:
	for id in temporary_blocks.keys():
		if Time.get_ticks_msec() >= int(temporary_blocks[id]):
			grid.set_point_solid(id,false)
			temporary_blocks.erase(id)
