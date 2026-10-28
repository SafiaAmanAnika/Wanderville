extends Camera2D
## Keep the whole viewport inside the campus, including after window resizing.
const Layout := preload("res://Scripts/network/CampusLayout.gd")
const START_ZOOM := 0.45
const INTERIOR_ZOOM := 0.3
var view_bounds := Rect2()
var _inside := false

func _ready() -> void:
	show_campus()
	get_viewport().size_changed.connect(_fit_view)

func show_campus() -> void:
	_inside = false
	# The fence is slightly skewed. Use the rectangle inside all four edges,
	# rather than its outer AABB, so no corner reveals the outside background.
	var points: Array = Layout.data.boundary
	var left := maxf(float(points[2][0]), float(points[3][0]))
	var right := minf(float(points[0][0]), float(points[1][0]))
	var top := maxf(float(points[0][1]), float(points[3][1]))
	var bottom := minf(float(points[1][1]), float(points[2][1]))
	set_view_bounds(Rect2(Vector2(left, top), Vector2(right-left, bottom-top)).grow(-32))

func show_interior(_interior: Node2D) -> void:
	# Houses share this camera but keep their original framing and free follow.
	_inside = true
	limit_left = -10000000
	limit_top = -10000000
	limit_right = 10000000
	limit_bottom = 10000000
	_fit_view()
	reset_smoothing()
	force_update_scroll()

func set_view_bounds(bounds: Rect2) -> void:
	view_bounds = bounds
	limit_left = ceili(bounds.position.x)
	limit_top = ceili(bounds.position.y)
	limit_right = floori(bounds.end.x)
	limit_bottom = floori(bounds.end.y)
	position = Vector2.ZERO
	offset = Vector2.ZERO
	_fit_view()
	reset_smoothing()
	force_update_scroll()

func _fit_view() -> void:
	if _inside:
		zoom = Vector2.ONE * INTERIOR_ZOOM
		force_update_scroll()
		return
	if not view_bounds.has_area(): return
	var size := get_viewport_rect().size
	var fit := maxf(size.x / view_bounds.size.x, size.y / view_bounds.size.y)
	zoom = Vector2.ONE * maxf(START_ZOOM, fit)
	force_update_scroll()
