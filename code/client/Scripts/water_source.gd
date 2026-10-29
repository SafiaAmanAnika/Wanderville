extends Area2D

const CampusLayout := preload("res://Scripts/network/CampusLayout.gd")

@export var refill_amount: int = 1
var player_in_range: bool = false
var _refilling := false
var _collector: Node2D

func _ready() -> void:
	_prepare_pond_interaction()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		if body.get("use_saved_appearance") == false: return
		# The sensor is only a cheap "maybe near". Whether the player really is
		# near is decided every frame by the server's own rule, below.
		_collector = body

func _on_body_exited(body: Node2D) -> void:
	if body == _collector:
		_collector = null
		_set_in_range(false)


func _physics_process(_delta: float) -> void:
	if is_instance_valid(_collector):
		# Same point and rule the server checks on a refill or a catch. The
		# sensor overlaps the player's feet, up to ~90 units below the origin,
		# so trusting it alone showed the prompt where the server said no.
		_set_in_range(CampusLayout.at_water(_collector.global_position))


func _set_in_range(value: bool) -> void:
	if value == player_in_range:
		return
	player_in_range = value
	if is_instance_valid(_collector) and _collector.has_method("set_near_water"):
		_collector.set_near_water(value)   # characters that can fish
	if value:
		var prompt := "Press Q to collect water"
		if is_instance_valid(_collector) and _collector.has_method("set_near_water"):
			prompt += "  ·  Press F to catch a fish"
		HousePrompt.show_text(prompt)
	else:
		HousePrompt.hide_text()


func _input(event: InputEvent) -> void:
	if GameState.menu_open or GameState.social_open:
		return
	if not player_in_range:
		return
	if not event.is_action_pressed("collect_water"):
		return
	if _refilling or not is_instance_valid(_collector): return
	if _collector.get("_busy") == true or _collector.get("fishing") == true: return
	if GameState.water_drops >= GameState.MAX_WATER:
		HousePrompt.flash("Water already full!")
		return
	if Global.is_logged_in() and not GameState.backend_ready:
		HousePrompt.flash("Game data has not loaded. Reconnecting; try Q again shortly.", 3.0, false)
		GameState.retry_backend()
		return
	_refilling = true
	AudioManager.play("collect_water")
	var version := Global.session_version
	var collector := _collector
	if collector.has_method("play_action"):
		await collector.play_action("fill_bucket")
	if not is_inside_tree(): return
	if version != Global.session_version or not is_instance_valid(collector) \
			or collector != _collector or not player_in_range or GameState.menu_open or GameState.social_open:
		_refilling = false
		return
	if GameState.water_drops >= GameState.MAX_WATER:
		_refilling = false
		return
	if Global.is_logged_in():
		var response: Dictionary = await APIClient.refill_water()
		_refilling = false
		if version != Global.session_version:
			return
		if bool(response.get("ok", false)):
			var data: Variant = APIClient.data_of(response)
			GameState.water_drops = int(data.get("water_remaining", 0))
			GameState.water_changed.emit(GameState.water_drops)
			HousePrompt.flash("Water refilled!", 2.0, false)
		else:
			# report_error puts the reason on the message line.
			GameState.report_error(response)
			await GameState.refresh_gameplay()
		return
	GameState.add_water(refill_amount)
	_refilling = false


func _prepare_pond_interaction() -> void:
	# The new map keeps solid pond banks on StaticBody2D; this child senses
	# players beside those banks without removing their physical collision.
	if get_parent() is StaticBody2D:
		var reach: float = float(CampusLayout.data.water_reach) / absf(global_scale.x)
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
