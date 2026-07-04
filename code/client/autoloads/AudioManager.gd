extends Node

const SETTINGS_FILE := "user://settings.cfg"

var music_volume: float = 80.0
var sfx_volume: float = 80.0

var _music_bus: AudioStreamPlayer
var _sfx_bus: AudioStreamPlayer


func _ready() -> void:
	_music_bus = AudioStreamPlayer.new()
	_music_bus.name = "MusicBus"
	add_child(_music_bus)
	_sfx_bus = AudioStreamPlayer.new()
	_sfx_bus.name = "SFXBus"
	add_child(_sfx_bus)
	_load_settings()


func set_music_volume(percent: float) -> void:
	music_volume = clampf(percent, 0.0, 100.0)
	var db := _percent_to_db(music_volume)
	_music_bus.volume_db = db
	_save_settings()


func set_sfx_volume(percent: float) -> void:
	sfx_volume = clampf(percent, 0.0, 100.0)
	var db := _percent_to_db(sfx_volume)
	_sfx_bus.volume_db = db
	_save_settings()


func play_music(stream: AudioStream) -> void:
	_music_bus.stream = stream
	_music_bus.play()


func play_sfx(stream: AudioStream) -> void:
	_sfx_bus.stream = stream
	_sfx_bus.play()


func stop_music() -> void:
	_music_bus.stop()


func _percent_to_db(percent: float) -> float:
	if percent <= 0.0:
		return -80.0
	return linear_to_db(percent / 100.0)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.save(SETTINGS_FILE)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SETTINGS_FILE)
	if err != OK:
		set_music_volume(80.0)
		set_sfx_volume(80.0)
		return
	music_volume = float(cfg.get_value("audio", "music_volume", 80.0))
	sfx_volume = float(cfg.get_value("audio", "sfx_volume", 80.0))
	set_music_volume(music_volume)
	set_sfx_volume(sfx_volume)
