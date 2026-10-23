extends Area2D
## Detection only: never adds a solid body or moves the player.
signal activated(action: StringName)

@export var action: StringName
@export var prompt := "[E] Interact"
@export var interaction_enabled := true


func available_to(player: CharacterBody2D) -> bool:
	return interaction_enabled and is_instance_valid(player) and overlaps_body(player)


func activate(player: CharacterBody2D) -> void:
	if available_to(player):
		activated.emit(action)
