extends Label

func _ready() -> void:
	GameState.water_changed.connect(_on_water_changed)
	_on_water_changed(GameState.water_drops)

func _on_water_changed(new_amount: int) -> void:
	text = "💧 %d / %d" % [new_amount, GameState.MAX_WATER]
