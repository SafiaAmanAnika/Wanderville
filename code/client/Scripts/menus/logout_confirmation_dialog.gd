extends ConfirmationDialog


func _ready() -> void:
	dialog_text = "Are you sure you want to log out?\nYour progress will be saved."
	ok_button_text = "Yes"
	cancel_button_text = "No"
	confirmed.connect(_on_confirmed)
	canceled.connect(_on_canceled)


func _on_confirmed() -> void:
	Global.clear_session()
	get_tree().change_scene_to_file("res://Scenes/menus/TitleScreen.tscn")


func _on_canceled() -> void:
	queue_free()
