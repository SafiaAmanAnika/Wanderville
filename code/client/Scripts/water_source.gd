extends Area2D

@export var refill_amount: int = 1
var player_in_range: bool = false

func _ready() -> void:
	var panel: Panel = $PromptLayer/Panel
	var label: Label = $PromptLayer/prompt

	var screen_size := get_viewport_rect().size
	var box_size := Vector2(260, 60)

	panel.custom_minimum_size = box_size
	panel.size = box_size
	panel.position = (screen_size - box_size) / 2

	# Red, rounded background
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.75, 0.1, 0.1, 0.85)
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = Color(1, 1, 1, 0.6)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)

	label.size = box_size
	label.position = panel.position
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color.WHITE)

	panel.visible = false
	label.visible = false
	label.text = "Press Q to collect water"
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = true
		$PromptLayer/prompt.text = "Press Q to collect water"
		$PromptLayer/Panel.visible = true
		$PromptLayer/prompt.visible = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = false
		$PromptLayer/Panel.visible = false
		$PromptLayer/prompt.visible = false


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("collect_water"):
		print("Q pressed")
	if GameState.menu_open:
		return
	if not player_in_range:
		return
	if not event.is_action_pressed("collect_water"):
		return
	if GameState.water_drops >= GameState.MAX_WATER:
		$PromptLayer/prompt.text = "Water already full!"
		print("Water already full!")
		return
	GameState.add_water(refill_amount)
