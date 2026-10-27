extends Button
## Resolution-independent music control: speaker waves when on, cross when muted.
var muted := false:
	set(value):
		muted=value
		set_pressed_no_signal(value)
		tooltip_text="Unmute music" if value else "Mute music"
		queue_redraw()

func _ready() -> void:
	toggle_mode=true
	custom_minimum_size=Vector2(56,56)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)

func _draw() -> void:
	var ink := Color("382820") if is_hovered() and not button_pressed else Color("f5e7d3")
	var origin := (size-Vector2(36,32))/2
	var outline := PackedVector2Array([Vector2(2,12),Vector2(9,12),Vector2(17,5),Vector2(17,27),Vector2(9,20),Vector2(2,20),Vector2(2,12)])
	for index in outline.size(): outline[index]+=origin
	draw_polyline(outline,ink,2.2,true)
	if muted:
		draw_line(origin+Vector2(24,11),origin+Vector2(34,21),ink,2.2,true)
		draw_line(origin+Vector2(24,21),origin+Vector2(34,11),ink,2.2,true)
	else:
		for radius in [9.0,15.0]: draw_arc(origin+Vector2(16,16),radius,-0.75,0.75,18,ink,2.2,true)
