extends Control
## First-time presentation of the same editor used by Wardrobe and Mirror.
var editor: PanelContainer
func _ready() -> void:
	SceneManager.show_journey_background(self,0.16)
	editor=preload("res://Scripts/customization/creator_panel.gd").new()
	add_child(editor); editor.begin("first_time")
	editor.close_requested.connect(SceneManager.goto_title)
	editor.saved.connect(func(_code: String): SceneManager.goto_world())
