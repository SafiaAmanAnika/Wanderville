extends Node

# Minimal global session state for auth.

var token: String = ""
var player_id: int = 0
var username: String = ""
var display_name: String = ""

const AUTH_FILE := "user://auth.cfg"


func is_logged_in() -> bool:
	return token != "" and player_id > 0


func set_session(new_token: String, player: Dictionary) -> void:
	token = new_token
	player_id = int(player.get("id", 0))
	username = str(player.get("username", ""))
	display_name = str(player.get("display_name", ""))
	save_session()


func save_session() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("auth", "token", token)
	cfg.set_value("auth", "player_id", player_id)
	cfg.set_value("auth", "username", username)
	cfg.set_value("auth", "display_name", display_name)
	cfg.save(AUTH_FILE)


func load_session() -> bool:
	var cfg := ConfigFile.new()
	var err := cfg.load(AUTH_FILE)
	if err != OK:
		return false
	token = str(cfg.get_value("auth", "token", ""))
	player_id = int(cfg.get_value("auth", "player_id", 0))
	username = str(cfg.get_value("auth", "username", ""))
	display_name = str(cfg.get_value("auth", "display_name", ""))
	return is_logged_in()


func clear_session() -> void:
	token = ""
	player_id = 0
	username = ""
	display_name = ""
	var dir := DirAccess.open("user://")
	if dir:
		dir.remove(AUTH_FILE)
