extends Node2D
# The inside of one house.
#   show_floor("honey")  → shows only that floor (or none with "")
#   spawn_position()     → where the player appears when entering
#   signal exited        → player walked into the Exit area

signal exited


func _ready() -> void:
	# inside view: no roof / outer layer
	for name in ["outer_layout", "outer_layer"]:
		var outer := get_node_or_null(name)
		if outer:
			outer.visible = false
	show_floor("")   # no floor until it's built
	var exit_area := get_node_or_null("Exit") as Area2D
	if exit_area:
		exit_area.body_entered.connect(func(body: Node) -> void:
			if body.is_in_group("player"):
				exited.emit())


func show_floor(floor_name: String) -> void:
	for f in HouseCatalog.FLOORS:
		var layer := get_node_or_null(f) as CanvasItem
		if layer:
			layer.visible = (f == floor_name)


func spawn_position() -> Vector2:
	var spawn := get_node_or_null("Spawn") as Node2D
	return spawn.global_position if spawn else global_position
