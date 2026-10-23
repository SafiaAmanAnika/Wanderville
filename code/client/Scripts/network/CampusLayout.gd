extends RefCounted
## Generated from the same world scene as the backend's collision snapshot.
const DATA_PATH := "res://data/campus_layout.json"
static var data: Dictionary = preload("res://data/campus_layout.json").data

static func spawn() -> Vector2:
    return Vector2(float(data.spawn[0]), float(data.spawn[1]))

static func polygon(values: Array) -> PackedVector2Array:
    var points := PackedVector2Array()
    for point in values:
        points.append(Vector2(float(point[0]), float(point[1])))
    return points

static func walkable(point: Vector2) -> bool:
    if not point.is_finite() or not Geometry2D.is_point_in_polygon(point, polygon(data.boundary)):
        return false
    for shape in data.collision:
        if Geometry2D.is_point_in_polygon(point, polygon(shape.points)):
            return false
    return true
