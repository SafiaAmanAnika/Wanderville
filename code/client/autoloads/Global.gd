extends Node

var token: String = ""
var player_id: int = 0
var username: String = ""
var display_name: String = ""
var remember_device: bool = true
var selected_character: String = ""
var selected_world_id: String = ""

# Email verification pass-through (set by SceneManager before scene change)
var _ev_message: String = ""
var _ev_success: bool = true

const AUTH_FILE := "user://auth.cfg"

const CHARACTER_SCENES: Dictionary = {
	"player1": "res://Scenes/player1.tscn",
	"farmer_female": "res://Scenes/player1.tscn",
}


func get_character_scene(character_id: String) -> PackedScene:
	var path = CHARACTER_SCENES.get(character_id, CHARACTER_SCENES["player1"])
	return load(path)


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
	cfg.set_value("auth", "remember_device", remember_device)
	cfg.set_value("auth", "selected_character", selected_character)
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
	remember_device = bool(cfg.get_value("auth", "remember_device", true))
	selected_character = str(cfg.get_value("auth", "selected_character", ""))
	if not remember_device:
		return false
	return is_logged_in()


func clear_session() -> void:
	token = ""
	player_id = 0
	username = ""
	display_name = ""
	selected_character = ""
	remember_device = true
	var dir := DirAccess.open("user://")
	if dir:
		dir.remove(AUTH_FILE)
