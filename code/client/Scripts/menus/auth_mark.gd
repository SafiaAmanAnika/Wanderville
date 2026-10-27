extends Control
var checkmark := false
func _draw() -> void:
	var c := size/2; var ink := Color("627c59")
	if checkmark:
		draw_polyline(PackedVector2Array([c+Vector2(-12,0),c+Vector2(-3,9),c+Vector2(15,-10)]),ink,4)
	else:
		draw_rect(Rect2(c-Vector2(19,13),Vector2(38,26)),ink,false,2)
		draw_polyline(PackedVector2Array([c+Vector2(-18,-12),c+Vector2(0,2),c+Vector2(18,-12)]),ink,2)
