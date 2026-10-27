extends Node2D
const CROP_ART = preload("res://Scripts/crop_catalog.gd")

@export var grid_size: Vector2i = Vector2i(1, 1)
@export var cell_size: float = 64.0
@export var plot_scene: PackedScene = preload("res://Scenes/farm_plot.tscn")

var plots: Array[Array] = []
var player_in_zone: bool = false

func _ready():
	_generate_grid()
	var zone = get_node_or_null("FarmZone")
	if zone:
		zone.body_entered.connect(_on_player_entered)
		zone.body_exited.connect(_on_player_exited)

func _generate_grid():
	for x in range(grid_size.x):
		plots.append([])
		for y in range(grid_size.y):
			var plot = plot_scene.instantiate()
			plot.position = Vector2(x * cell_size, y * cell_size)
			plot.name = "Plot_%d_%d" % [x, y]
			add_child(plot)
			plots[x].append(plot)

func _on_player_entered(body):
	if body.is_in_group("player"):
		player_in_zone = true
		print("FARM ZONE: Press E to interact")

func _on_player_exited(body):
	if body.is_in_group("player"):
		player_in_zone = false

func _input(event):
	if not player_in_zone or not event.is_action_pressed("interact"):
		return

	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return

	var plot = _get_nearest_plot(player.global_position)
	if not plot:
		return

	match plot.state:
		plot.State.EMPTY:
			plot.till()
			print("TILLED")
		plot.State.TILLED:
			_auto_plant(plot)
		plot.State.PLANTED:
			plot.water()
			print("WATERED")
		plot.State.HARVESTABLE:
			var harvested = plot.harvest()
			print("HARVESTED: ", harvested)

func _get_nearest_plot(player_pos: Vector2) -> Node:
	var nearest = null
	var min_dist = INF

	for x in range(grid_size.x):
		for y in range(grid_size.y):
			var plot = plots[x][y]
			var dist = player_pos.distance_to(plot.global_position)
			if dist < min_dist:
				min_dist = dist
				nearest = plot

	if min_dist < cell_size * 0.8:
		return nearest
	return null

func _auto_plant(plot):
	# Every crop that has art, so a seed can never be planted without a sprite.
	for seed in CROP_ART.ids():
		if GameState.seed_inventory.get(seed, 0) > 0:
			if plot.plant(seed):
				GameState.seed_inventory[seed] -= 1
				GameState.seed_changed.emit(seed)
				print("PLANTED: ", seed)
				return
	print("NO SEEDS")
