extends SceneTree
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	if not value: failures += 1; push_error(label)
func run() -> void:
	root.get_node("Global").token = ""
	root.get_node("APIClient").base_url = "http://127.0.0.1:1"
	var ui: Node = load("res://Scripts/social/proximity_social.gd").new()
	root.add_child(ui)
	await process_frame
	ui._proximity({"nearby":[{"player_id":99,"username":"A very long nearby player name","distance":50,"show_prompt":true}]})
	check(not ui._scroll.visible, "Nearby presence never opens the panel")
	ui._toggle.pressed.emit()
	await process_frame; await process_frame
	check(ui._scroll.visible, "User can open Nearby")
	check(ui._panel.size.x <= 420, "Panel stays compact")
	check(ui._panel.get_global_rect().end.y <= ui.get_viewport().get_visible_rect().size.y, "Panel stays inside viewport")
	ui._text.show(); ui._text.grab_focus()
	await process_frame
	ui._toggle.pressed.emit()
	await process_frame
	check(not ui._scroll.visible and not ui._text.has_focus(), "Closing releases typing focus")
	ui._proximity({"nearby":[{"player_id":99,"username":"Friend","distance":50,"show_prompt":true}]})
	check(not ui._scroll.visible, "Updates do not reopen dismissed UI")
	check(not root.get_node("GameState").social_open, "Movement resumes after closing")
	ui.queue_free(); await process_frame
	print("NEARBY_UI_CHECK failures=", failures)
	quit(failures)
