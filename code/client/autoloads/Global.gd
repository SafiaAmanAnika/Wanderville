extends Node

# Minimal global session state for auth.

var token: String = ""
var player_id: int = 0
var username: String = ""
var display_name: String = ""


func is_logged_in() -> bool:
	return token != "" and player_id > 0


func set_session(new_token: String, player: Dictionary) -> void:
	token = new_token
	player_id = int(player.get("id", 0))
	username = str(player.get("username", ""))
	display_name = str(player.get("display_name", ""))


func clear_session() -> void:
	token = ""
	player_id = 0
	username = ""
	display_name = ""
