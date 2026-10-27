extends "res://Scripts/lobby_player_spawner.gd"
## The social lobby spawns the saved selected character at PlayerSpawn.

func _ready() -> void:
	super._ready()
	var friends := preload("res://Scripts/social/lobby_online_friends.gd").new()
	friends.name = "OnlineFriends"
	add_child(friends)
