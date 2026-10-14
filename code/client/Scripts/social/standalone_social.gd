extends Node2D
## Lightweight Godot social client for testing without loading the farm map.
var _login: PanelContainer
var _username: LineEdit
var _password: LineEdit
var _status: Label
var _actor: Node2D
var _players: Array = []
var _logging_in := false


func _ready() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_login = PanelContainer.new()
	_login.position = Vector2(40, 40)
	_login.custom_minimum_size = Vector2(350, 200)
	layer.add_child(_login)
	var box := VBoxContainer.new()
	_login.add_child(box)
	var title := Label.new()
	title.text = "Wanderville · Native social test client"
	box.add_child(title)
	_username = LineEdit.new()
	_username.placeholder_text = "Username"
	box.add_child(_username)
	_password = LineEdit.new()
	_password.placeholder_text = "Password"
	_password.secret = true
	box.add_child(_password)
	var login := Button.new()
	login.text = "Log in"
	login.pressed.connect(_sign_in)
	_password.text_submitted.connect(func(_value: String) -> void: _sign_in())
	box.add_child(login)
	_status = Label.new()
	_status.text = "Use two accounts. Move with arrow keys."
	box.add_child(_status)
	APIClient.realtime.snapshot_received.connect(func(data: Dictionary) -> void:
		_players = data.get("players", [])
		queue_redraw()
	)


func _sign_in() -> void:
	if _logging_in:
		return
	_logging_in = true
	var response: Dictionary = await APIClient.login(_username.text.strip_edges(), _password.text)
	_logging_in = false
	if not response.get("ok", false):
		_status.text = APIClient.error_text(response)
		return
	var data: Dictionary = APIClient.data_of(response)
	Global.set_session(data["access_token"], data["player"], data["refresh_token"])
	_password.clear()
	if not await GameState.load_from_backend():
		_status.text = "Could not load account state. Try again."
		return
	_login.hide()
	_actor = Node2D.new()
	_actor.add_to_group("player")
	add_child(_actor)
	var camera := Camera2D.new()
	_actor.add_child(camera)
	APIClient.realtime.standalone_enabled = true
	add_child(preload("res://Scenes/world_hud.tscn").instantiate())


func _process(delta: float) -> void:
	if _actor != null and APIClient.realtime.connected and not GameState.social_open and not GameState.menu_open:
		_actor.position += Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down") * 200.0 * delta
	queue_redraw()


func _draw() -> void:
	for player in _players:
		var own := int(player["player_id"]) == Global.player_id
		var position := _actor.position if own and _actor != null else Vector2(float(player["x"]), float(player["y"]))
		if own:
			draw_arc(position, 600, 0, TAU, 100, Color(0.3, 0.5, 0.5, 0.3), 2)
		draw_circle(position, 16, Color.CORNFLOWER_BLUE if own else Color.CORAL)
		draw_string(ThemeDB.fallback_font, position + Vector2(-45, 35), str(player["username"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 18)


func _exit_tree() -> void:
	APIClient.realtime.standalone_enabled = false
	APIClient.realtime.stop()
