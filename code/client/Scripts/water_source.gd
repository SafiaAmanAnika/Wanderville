extends Area2D

@export var refill_amount: int = 1
var player_in_range: bool = false
var _refilling := false

func _ready() -> void:
	_prepare_pond_interaction()
	var panel: Panel = $PromptLayer/Panel
	var label: Label = $PromptLayer/prompt

	var screen_size := get_viewport_rect().size
	var box_size := Vector2(560, 60)

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
	label.add_theme_font_size_override("font_size", WoodPanel.SIZE_STATUS)
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
		if body.has_method("set_near_water"):   # characters that can fish
			body.set_near_water(true)
			$PromptLayer/prompt.text = "Press Q to collect water | Press F to catch a fish"
		$PromptLayer/Panel.visible = true
		$PromptLayer/prompt.visible = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = false
		if body.has_method("set_near_water"):
			body.set_near_water(false)
		$PromptLayer/Panel.visible = false
		$PromptLayer/prompt.visible = false


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("collect_water"):
		print("Q pressed")
	if GameState.menu_open or GameState.social_open:
		return
	if not player_in_range:
		return
	if not event.is_action_pressed("collect_water"):
		return
	if GameState.water_drops >= GameState.MAX_WATER:
		$PromptLayer/prompt.text = "Water already full!"
		print("Water already full!")
		return
	if Global.is_logged_in():
		if _refilling or not GameState.backend_ready:
			return
		_refilling = true
		var version := Global.session_version
		var response: Dictionary = await APIClient.refill_water()
		_refilling = false
		if version != Global.session_version:
			return
		if bool(response.get("ok", false)):
			var data: Variant = APIClient.data_of(response)
			GameState.water_drops = int(data.get("water_remaining", 0))
			GameState.water_changed.emit(GameState.water_drops)
			$PromptLayer/prompt.text = "Water refilled!"
		else:
			$PromptLayer/prompt.text = APIClient.error_text(response)
			GameState.report_error(response)
			await GameState.refresh_gameplay()
		return
	GameState.add_water(refill_amount)


func _prepare_pond_interaction() -> void:
	# The new map keeps solid pond banks on StaticBody2D; this child senses
	# players beside those banks without removing their physical collision.
	if get_parent() is StaticBody2D:
		var layout := preload("res://Scripts/network/CampusLayout.gd")
		var reach: float = float(layout.data.water_reach) / absf(global_scale.x)
		for bank in get_parent().get_children():
			if not bank is CollisionPolygon2D:
				continue
			var points := PackedVector2Array()
			for point in bank.polygon:
				points.append(bank.transform * point)
			for outline in Geometry2D.offset_polygon(points, reach):
				var sensor := CollisionPolygon2D.new()
				sensor.polygon = outline
				add_child(sensor)
	if not has_node("PromptLayer"):
		var layer := CanvasLayer.new()
		layer.name = "PromptLayer"
		add_child(layer)
		var panel := Panel.new()
		panel.name = "Panel"
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(panel)
		var label := Label.new()
		label.name = "prompt"
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(label)
