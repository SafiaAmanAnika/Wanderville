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

## The backend's at_water() (app/modules/world/geometry.py), line for line:
## inside a pond polygon or within water_reach of one of its edges. The server
## checks the player's origin with this rule before a refill or a catch, so
## the client must ask the same question about the same point.
static func at_water(point: Vector2) -> bool:
    var reach := float(data.water_reach)
    for shape in data.water:
        var points := polygon(shape.points)
        if Geometry2D.is_point_in_polygon(point, points):
            return true
        for i in points.size():
            var closest := Geometry2D.get_closest_point_to_segment(point, points[i], points[(i + 1) % points.size()])
            if point.distance_to(closest) <= reach:
                return true
    return false
