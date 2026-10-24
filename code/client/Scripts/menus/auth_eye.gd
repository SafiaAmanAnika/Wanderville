extends Button
var field: LineEdit
func _ready() -> void:
	custom_minimum_size=Vector2(46,46); toggle_mode=true
	tooltip_text="Show password"
	toggled.connect(func(shown: bool):
		field.secret=not shown
		tooltip_text="Hide password" if shown else "Show password"
		queue_redraw()
	)
func _draw() -> void:
	var c := size/2; var ink := Color("85634d")
	var points := PackedVector2Array()
	for i in 25:
		var angle := i*TAU/24
		points.append(c+Vector2(cos(angle)*10,sin(angle)*6))
	draw_polyline(points,ink,1.8,true); draw_circle(c,2.7,ink)
	if button_pressed: draw_line(c+Vector2(-12,10),c+Vector2(12,-10),ink,1.8,true)
