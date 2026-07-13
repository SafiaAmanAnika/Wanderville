extends Node

var token: String = ""
var refresh_token: String = ""
var player_id: int = 0
var username: String = ""
var display_name: String = ""
var email: String = ""
var remember_device: bool = true
var selected_character: String = ""
var selected_world_id: String = ""

# Email verification pass-through (set by SceneManager before scene change)
var _ev_message: String = ""
var _ev_success: bool = true
var _ev_state: String = "waiting"

# Deep link tokens (parsed from command line args on startup)
var pending_verify_token: String = ""
var pending_reset_token: String = ""

const AUTH_FILE := "user://auth.cfg"

const CHARACTER_SCENES: Dictionary = {
	"player1": "res://Scenes/player1.tscn",
	"farmer_female": "res://Scenes/player1.tscn",
}


func _ready() -> void:
	parse_deep_link()


func get_character_scene(character_id: String) -> PackedScene:
	var path = CHARACTER_SCENES.get(character_id, CHARACTER_SCENES["player1"])
	return load(path)


func is_logged_in() -> bool:
	return token != "" and player_id > 0


func has_completed_setup() -> bool:
	return selected_character != "" and selected_world_id != ""


func set_session(new_token: String, player: Dictionary, new_refresh: String = "") -> void:
	token = new_token
	if new_refresh != "":
		refresh_token = new_refresh
	player_id = int(player.get("id", 0))
	username = str(player.get("username", ""))
	display_name = str(player.get("display_name", ""))
	email = str(player.get("email", ""))
	save_session()


func save_session() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("auth", "token", token)
	cfg.set_value("auth", "refresh_token", refresh_token)
	cfg.set_value("auth", "player_id", player_id)
	cfg.set_value("auth", "username", username)
	cfg.set_value("auth", "display_name", display_name)
	cfg.set_value("auth", "email", email)
	cfg.set_value("auth", "remember_device", remember_device)
	cfg.set_value("auth", "selected_character", selected_character)
	cfg.set_value("auth", "selected_world_id", selected_world_id)
	cfg.save(AUTH_FILE)


func load_session() -> bool:
	var cfg := ConfigFile.new()
	var err := cfg.load(AUTH_FILE)
	if err != OK:
		return false
	token = str(cfg.get_value("auth", "token", ""))
	refresh_token = str(cfg.get_value("auth", "refresh_token", ""))
	player_id = int(cfg.get_value("auth", "player_id", 0))
	username = str(cfg.get_value("auth", "username", ""))
	display_name = str(cfg.get_value("auth", "display_name", ""))
	email = str(cfg.get_value("auth", "email", ""))
	remember_device = bool(cfg.get_value("auth", "remember_device", true))
	selected_character = str(cfg.get_value("auth", "selected_character", ""))
	selected_world_id = str(cfg.get_value("auth", "selected_world_id", ""))
	if not remember_device:
		return false
	return is_logged_in()


func clear_session() -> void:
	token = ""
	refresh_token = ""
	player_id = 0
	username = ""
	display_name = ""
	email = ""
	selected_character = ""
	selected_world_id = ""
	remember_device = true
	var dir := DirAccess.open("user://")
	if dir:
		dir.remove(AUTH_FILE)


func parse_deep_link() -> void:
	var args := PackedStringArray(OS.get_cmdline_args())
	for arg in args:
		if arg.begins_with("wanderville://"):
			var url := arg.substr("wanderville://".length())
			var parts := url.split("?")
			var path := parts[0]
			var params := {}
			if parts.size() > 1:
				params = _parse_query(parts[1])
			match path:
				"verify":
					pending_verify_token = str(params.get("token", ""))
				"reset-password":
					pending_reset_token = str(params.get("token", ""))


func _parse_query(query: String) -> Dictionary:
	var result := {}
	for pair in query.split("&"):
		var kv := pair.split("=")
		if kv.size() == 2:
			result[kv[0]] = kv[1].uri_decode()
	return result
