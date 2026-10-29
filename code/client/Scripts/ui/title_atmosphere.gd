extends Control
## A quiet frame and drifting fireflies, drawn without blocking menu input.
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var border := Rect2(Vector2(24, 24), size - Vector2(48, 48))
	draw_rect(border, Color(1.0, 0.86, 0.59, 0.35), false, 1.0)
	for corner in [border.position, Vector2(border.end.x, border.position.y), border.end, Vector2(border.position.x, border.end.y)]:
		draw_circle(corner, 3.0, Color("e3bd78"))
	for index in 24:
		var phase := float(index) * 2.39996
		var x := fposmod(float(index) * 173.0 + sin(_time * 0.16 + phase) * 28.0, size.x)
		var y := fposmod(float(index) * 97.0 - _time * (3.0 + index % 4), size.y)
		var alpha := (sin(_time * 0.7 + phase) + 1.0) * 0.18
		draw_circle(Vector2(x, y), 5.0, Color(1.0, 0.78, 0.33, alpha * 0.15))
		draw_rect(Rect2(Vector2(x, y), Vector2(2, 2)), Color(1.0, 0.88, 0.55, alpha))
