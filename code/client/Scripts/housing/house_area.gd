extends Area2D
# The only place on the map where a house may be built.
# Attach to an Area2D that has one CollisionPolygon2D child.
#
# house_manager.gd finds this through the "house_area" group and uses it for
# two things: whether J is allowed right now, and whether the ghost may land.

@onready var _poly: CollisionPolygon2D = $CollisionPolygon2D

var player_inside := false


func _ready() -> void:
	add_to_group("house_area")
	body_entered.connect(_on_entered)
	body_exited.connect(_on_exited)
	# Area2D only signals on crossing, so a player who spawns inside is missed.
	_check_at_start()


func _check_at_start() -> void:
	await get_tree().physics_frame
	for body in get_overlapping_bodies():
		if body.is_in_group("player"):
			_on_entered(body)
			return


# Is this world-space point inside the buildable polygon?
func contains(global_point: Vector2) -> bool:
	if _poly == null:
		return true   # no polygon set up: don't lock the player out of housing
	return Geometry2D.is_point_in_polygon(_poly.to_local(global_point), _poly.polygon)


func _on_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	player_inside = true
	if GameState.house["stage"] == "none":
		HousePrompt.show_text("Press J to buy a house")


func _on_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	player_inside = false
	HousePrompt.hide_text()
