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
	# C cuts the current season's trees for wood.
	var cutter := preload("res://Scripts/trees/tree_cutter.gd").new()
	cutter.name = "TreeCutter"
	add_child(cutter)
	var effects = get_node_or_null("../../SeasonalEffects")
	if effects != null:
		set_tree_season(effects.get_current_season())
