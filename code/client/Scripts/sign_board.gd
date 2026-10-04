extends Area2D

@onready var hint_label: Label = $Label

var player_near: bool = false

func _ready():
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _process(_delta):
	if player_near and (Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("ui_accept")) and not GameState.menu_open and not GameState.social_open:
		open_menu()

func _on_body_entered(body: Node2D):
	if body.is_in_group("player"):
		player_near = true
		hint_label.text = "Press E to Open"
		hint_label.visible = true

func _on_body_exited(body: Node2D):
	if body.is_in_group("player"):
		player_near = false
		hint_label.visible = false

func open_menu():
	var farm_menu = get_tree().get_first_node_in_group("farm_menu")
	if farm_menu:
		farm_menu.open()
		hint_label.visible = false
