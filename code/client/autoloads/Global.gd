extends Node

signal session_changed
signal appearance_changed

var token: String = ""
var session_version := 0
var refresh_token: String = ""
var player_id: int = 0
var username: String = ""
var display_name: String = ""
var email: String = ""
var about_me: String = ""   # local-only profile text; server sync not available yet
var remember_device: bool = true
var selected_character: String = ""
var selected_world_id: String = ""

# ── Appearance (local-only until the server stores it) ──────────────
# Index into the matching palette array; 0 is the character's default look.
var hair_style: int = 0
var cloth_style: int = 0
var skin_tone: int = 0
# Retained for old save compatibility; generated appearances are no longer applied.
var modular_look: Dictionary = {}

# Legacy preference values retained for older saves. Original artwork is unchanged.
const SKIN_TONES: Array[Color] = [
	Color(1.0, 0.87, 0.72),   # default warm
	Color(0.98, 0.82, 0.66),
	Color(0.92, 0.74, 0.56),
	Color(0.82, 0.63, 0.45),
	Color(0.70, 0.51, 0.35),
	Color(0.56, 0.39, 0.26),
]

const HAIR_COLORS: Array[Color] = [
	Color(0.55, 0.20, 0.09),   # default red-brown
	Color(0.16, 0.12, 0.10),   # black
	Color(0.35, 0.22, 0.12),   # chestnut
	Color(0.85, 0.72, 0.42),   # blonde
	Color(0.72, 0.28, 0.42),   # pink
	Color(0.35, 0.45, 0.62),   # blue
]

const CLOTH_COLORS: Array[Color] = [
	Color(0.93, 0.87, 0.72),   # default cream
	Color(0.62, 0.28, 0.24),   # red
	Color(0.30, 0.44, 0.30),   # green
	Color(0.28, 0.38, 0.58),   # blue
	Color(0.72, 0.60, 0.30),   # gold
	Color(0.45, 0.30, 0.52),   # purple
]

const HAIR_STYLES := ["Default", "Short", "Long"]

# Email verification pass-through (set by SceneManager before scene change)
var _ev_message: String = ""
var _ev_success: bool = true
var _ev_state: String = "waiting"

# Deep link tokens (parsed from command line args on startup)
var pending_verify_token: String = ""
var pending_reset_token: String = ""

const AUTH_FILE := "user://auth.cfg"


func _auth_file() -> String:
	# Local development and the hosted game must not overwrite each other's login.
	return "user://auth_%s.cfg" % APIClient.base_url.sha256_text()

const CHARACTER_SCENES: Dictionary = {
	"player1": "res://Scenes/player1.tscn",
	"farmer_female": "res://Scenes/player1.tscn",
	"girl_a": "res://Scenes/charagirlA.tscn",
	"girl_b": "res://Scenes/charagirlB.tscn",
	"girl_c": "res://Scenes/charagirlC.tscn",
	"boy_a": "res://Scenes/charaboyA.tscn",
	"boy_b": "res://Scenes/charaboyB.tscn",
	"boy_c": "res://Scenes/charaboyC.tscn",
}

# Characters shown on the select screen. "folder" is only used for the card picture.
const CHARACTERS: Dictionary = {
	"farmer_female": {"name": "Female Farmer", "folder": ""},
	"girl_a": {"name": "Girl A", "folder": "res://Assets/charas/CharacterA"},
	"girl_b": {"name": "Girl B", "folder": "res://Assets/charas/CharacterB"},
	"girl_c": {"name": "Girl C", "folder": "res://Assets/charas/CharacterC"},
	"boy_a": {"name": "Boy A", "folder": "res://Assets/charas/CharacterA_Male"},
	"boy_b": {"name": "Boy B", "folder": "res://Assets/charas/CharacterB_Male"},
	"boy_c": {"name": "Boy C", "folder": "res://Assets/charas/CharacterC_Male"},
}


func _ready() -> void:
	parse_deep_link()


func get_character_scene(character_id: String) -> PackedScene:
	var path: String = CHARACTER_SCENES.get(character_id, CHARACTER_SCENES["player1"])
	if ResourceLoader.exists(path):
		var scene := load(path) as PackedScene
		if scene != null: return scene
	# Keep the original farmer as a stable spawn fallback. Do not rewrite the
	# saved ID: a temporarily unavailable character can return on the next load.
	return load(CHARACTER_SCENES["player1"]) as PackedScene


func skin_color() -> Color:
	return SKIN_TONES[clampi(skin_tone, 0, SKIN_TONES.size() - 1)]


func hair_color() -> Color:
	return HAIR_COLORS[clampi(hair_style, 0, HAIR_COLORS.size() - 1)]


func cloth_color() -> Color:
	return CLOTH_COLORS[clampi(cloth_style, 0, CLOTH_COLORS.size() - 1)]


func set_appearance(new_hair: int, new_cloth: int, new_skin: int) -> void:
	hair_style = clampi(new_hair, 0, HAIR_COLORS.size() - 1)
	cloth_style = clampi(new_cloth, 0, CLOTH_COLORS.size() - 1)
	skin_tone = clampi(new_skin, 0, SKIN_TONES.size() - 1)
	save_session()
	appearance_changed.emit()


func is_logged_in() -> bool:
	return token != "" and player_id > 0


func has_completed_setup() -> bool:
	return selected_character != "" and selected_world_id != ""


func set_session(new_token: String, player: Dictionary, new_refresh: String = "") -> void:
	session_version += 1
	APIClient.realtime.clear_session()
	selected_character = ""
	selected_world_id = ""
	modular_look = {}
	GameState.reset()
	token = new_token
	refresh_token = new_refresh
	player_id = int(player.get("id", 0))
	username = str(player.get("username", ""))
	display_name = str(player.get("display_name", ""))
	email = str(player.get("email", ""))
	save_session()
	session_changed.emit()


func save_session() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("auth", "token", token)
	cfg.set_value("auth", "refresh_token", refresh_token)
	cfg.set_value("auth", "player_id", player_id)
	cfg.set_value("auth", "username", username)
	cfg.set_value("auth", "display_name", display_name)
	cfg.set_value("auth", "email", email)
	cfg.set_value("auth", "about_me", about_me)
	cfg.set_value("auth", "remember_device", remember_device)
	cfg.set_value("auth", "selected_character", selected_character)
	cfg.set_value("auth", "selected_world_id", selected_world_id)
	cfg.set_value("look", "hair_style", hair_style)
	cfg.set_value("look", "cloth_style", cloth_style)
	cfg.set_value("look", "skin_tone", skin_tone)
	cfg.set_value("look", "modular", modular_look)
	cfg.save(_auth_file())


func load_session() -> bool:
	var cfg := ConfigFile.new()
	var err := cfg.load(_auth_file())
	# Migrate the previous unscoped login only for its original project server.
	if err != OK and APIClient.base_url == str(ProjectSettings.get_setting("network/wanderville_api_url", APIClient.DEFAULT_BASE_URL)).rstrip("/"):
		err = cfg.load(AUTH_FILE)
	if err != OK:
		return false
	if not bool(cfg.get_value("auth", "remember_device", true)):
		return false
	session_version += 1
	token = str(cfg.get_value("auth", "token", ""))
	refresh_token = str(cfg.get_value("auth", "refresh_token", ""))
	player_id = int(cfg.get_value("auth", "player_id", 0))
	username = str(cfg.get_value("auth", "username", ""))
	display_name = str(cfg.get_value("auth", "display_name", ""))
	email = str(cfg.get_value("auth", "email", ""))
	about_me = str(cfg.get_value("auth", "about_me", ""))
	remember_device = bool(cfg.get_value("auth", "remember_device", true))
	selected_character = str(cfg.get_value("auth", "selected_character", ""))
	selected_world_id = str(cfg.get_value("auth", "selected_world_id", ""))
	hair_style = int(cfg.get_value("look", "hair_style", 0))
	cloth_style = int(cfg.get_value("look", "cloth_style", 0))
	skin_tone = int(cfg.get_value("look", "skin_tone", 0))
	var saved_look = cfg.get_value("look", "modular", {})
	modular_look = saved_look if saved_look is Dictionary else {}
	if not remember_device:
		return false
	session_changed.emit()
	return is_logged_in()


func clear_session() -> void:
	session_version += 1
	APIClient.realtime.clear_session()
	GameState.reset()
	token = ""
	refresh_token = ""
	player_id = 0
	username = ""
	display_name = ""
	email = ""
	about_me = ""
	selected_character = ""
	selected_world_id = ""
	remember_device = true
	hair_style = 0
	cloth_style = 0
	skin_tone = 0
	modular_look = {}
	var dir := DirAccess.open("user://")
	if dir:
		dir.remove(_auth_file())
		if APIClient.base_url == str(ProjectSettings.get_setting("network/wanderville_api_url", APIClient.DEFAULT_BASE_URL)).rstrip("/"):
			dir.remove(AUTH_FILE)
	session_changed.emit()


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
