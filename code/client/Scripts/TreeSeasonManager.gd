extends Node2D

@onready var palm_trees: Node2D = $Palm_trees
@onready var summer_trees: Node2D = $Summer
@onready var autumn_trees: Node2D = $Autumn
@onready var winter_trees: Node2D = $Winter
@onready var spring_trees: Node2D = $Spring


func set_tree_season(season: int) -> void:
	palm_trees.visible = true
	
	summer_trees.visible = season == 0
	autumn_trees.visible = season == 1
	winter_trees.visible = season == 2
	spring_trees.visible = season == 3

func _ready() -> void:
	var seasonal_effects = get_node_or_null("/root/World/SeasonalEffects")

	if seasonal_effects != null:
		set_tree_season(seasonal_effects.get_current_season())
