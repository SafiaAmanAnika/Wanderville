extends "res://Scripts/lobby_player_spawner.gd"
## The social lobby spawns the saved selected character at PlayerSpawn.

func _ready() -> void:
	super._ready()
	var frames := preload("res://Scripts/chara_frames.gd")
	var folder := "res://Assets/charas/CharacterC"
	if not frames.longer_leg_folder(folder).is_empty():
		$Receptionist.sprite_frames = frames.preview_frames(folder, "idle")
		$Receptionist.play("idle_front")
