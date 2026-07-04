extends Control

@onready var _grid: GridContainer = %WorldGrid
@onready var _enter_button: Button = %EnterWorldButton
@onready var _back_button: Button = %BackButton
@onready var _status_label: Label = %StatusLabel

var _selected_world_id: String = ""
var _world_card_scene: PackedScene = preload("res://Scenes/components/WorldCard.tscn")


func _ready() -> void:
	_enter_button.disabled = true
	_enter_button.pressed.connect(_on_enter_world)
	_back_button.pressed.connect(_on_back)
	_fetch_worlds()


func _fetch_worlds() -> void:
	_status_label.text = "Loading worlds..."

	var res := await APIClient.get_my_world(Global.token)

	if not bool(res.get("ok", false)):
		var body = res.get("body", {})
		var msg := "Failed to load worlds."
		if typeof(body) == TYPE_DICTIONARY:
			msg = str(body.get("message", msg))
		_status_label.text = msg
		return

	_status_label.text = ""

	var body = res.get("body", {})
	var data = body.get("data", {}) if typeof(body) == TYPE_DICTIONARY else {}
	var worlds: Array[Dictionary] = []
	if typeof(data) == TYPE_DICTIONARY and data.has("id"):
		worlds = [data]

	for child in _grid.get_children():
		child.queue_free()

	if worlds.is_empty():
		_status_label.text = "No worlds found."
		return

	for w in worlds:
		var card := _world_card_scene.instantiate()
		_grid.add_child(card)
		card.set_world(str(w.get("id", "")), str(w.get("name", "Unnamed World")))
		card.pressed.connect(_on_world_clicked.bind(w, card))

	if worlds.size() == 1:
		var only_card = _grid.get_child(0)
		_select_world(worlds[0], only_card)


func _on_world_clicked(world: Dictionary, card: Button) -> void:
	_select_world(world, card)


func _select_world(world: Dictionary, selected_card: Button) -> void:
	_selected_world_id = str(world.get("id", ""))
	_enter_button.disabled = false

	for card in _grid.get_children():
		if card == selected_card:
			card.modulate = Color(1, 1, 1, 1)
			if card.has_method("set_selected"):
				card.set_selected(true)
		else:
			card.modulate = Color(0.7, 0.7, 0.7, 0.7)
			if card.has_method("set_selected"):
				card.set_selected(false)


func _on_enter_world() -> void:
	if _selected_world_id == "":
		return
	Global.selected_world_id = _selected_world_id
	SceneManager.goto_world()


func _on_back() -> void:
	SceneManager.goto_map_selection()
