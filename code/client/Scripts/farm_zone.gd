extends Area2D

@onready var hint_label: Label = $Label

func _ready():
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	hint_label.visible = false

func _on_body_entered(body: Node2D):
	if body.is_in_group("player"):
		hint_label.visible = true
		hint_label.text = "Press E to Farm"

func _on_body_exited(body: Node2D):
	if body.is_in_group("player"):
		hint_label.visible = false
		if GameState.farm_mode != "none":
			GameState.set_mode("none")
