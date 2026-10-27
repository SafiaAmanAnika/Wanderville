extends Node
## Every sound in the game goes through here.
##
## Two buses are created at runtime so the sliders in the settings overlay keep
## working untouched — they now move a whole bus instead of a single player:
##   Music  one looping track at a time (scene background music)
##   SFX    short one-shots from a voice pool, plus named looping effects
##
## Sounds are named by the short keys in SOUNDS, never by path:
##   AudioManager.play("button_click")              one-shot
##   AudioManager.play_music("music_marketplace")   looping track, fades in
##   AudioManager.start_loop("walk")                looping effect
##   AudioManager.stop_loop("walk")
##
## Button clicks and hovers are wired automatically for every BaseButton in the
## game (see _wire_button), so no menu script has to ask for them. Give a button
## `set_meta("silent", true)` to opt it out.

const SETTINGS_FILE := "user://settings.cfg"
const SOUND_DIR := "res://Assets/sounds/"

const SFX_VOICES := 12      ## how many one-shots can overlap
const HOVER_GAP := 0.06     ## shortest gap between two hover blips, in seconds
const MUSIC_FADE := 0.6     ## crossfade when the track changes, in seconds
const QUIT_SOUND_MAX := 2.5 ## never hold the window open longer than this

## key -> file under SOUND_DIR
const SOUNDS := {
	# chatbox
	"msg_sent": "Chatbox/Msg_sent.mp3",
	"msg_received": "Chatbox/Msg_received.mp3",
	# notifications
	"notification": "Notification/Notification_1.mp3",
	# fishing mini game
	"minigame_music": "Minigame/Minigame_2.mp3",
	"minigame_success": "Minigame/Success.mp3",
	"minigame_failure": "Minigame/Failure.mp3",
	# pets
	"meow": "Pet/Meow.mp3",
	"woof": "Pet/Woof.mp3",
	# player
	"walk": "Player/Walking.mp3",
	"level_up": "Player/Leveling_up.wav",
	"aura": "Player/Gaining_aura.wav",
	# farming
	"till": "Farming/Digging_soil.mp3",
	"plant": "Farming/Planting.mp3",
	"water_crop": "Farming/Watering_plants.mp3",
	"harvest": "Farming/Harvesting.mp3",
	"collect_water": "Farming/Collecting_water.mp3",
	"cut_wood": "Farming/Cutting_wood_1.mp3",   # 10 s; capped at 3 below
	# housing
	"furniture": "Furniture/Furniture_2.mp3",
	# ui
	"button_click": "Wanderville/Button_clicking.mp3",
	"button_hover": "Wanderville/Button_hover.mp3",
	"game_exit": "Wanderville/Game_exit_1.wav",
	# music
	"music_world": "Wanderville/Wanderville_Background.mp3",
	"music_marketplace": "Marketplace/Fair_2.mp3",
	"music_menu": "Wanderville/Landing_page.mp3",
}

## scene file -> music key. A scene that is not listed falls back to
## DEFAULT_MUSIC, so leaving the marketplace or the map stops their track on its
## own and no scene has to remember to clean up after itself.
const SCENE_MUSIC := {
	"res://Scenes/menus/TitleScreen.tscn": "music_menu",
	"res://Scenes/world.tscn": "music_world",
	"res://Scenes/map.tscn": "music_world",
	"res://Scenes/map2.tscn": "music_world",
	"res://Scenes/SocialLobby.tscn": "music_world",
	"res://Scenes/CustomizationLobby.tscn": "music_world",
	"res://Scenes/marketplace.tscn": "music_marketplace",
}
## "" = silence in the menus. Set to "music_menu" for the landing page theme.
const DEFAULT_MUSIC := ""

## Per-track trim in dB, relative to the music slider. Only tracks that need to
## sit under the others are listed; anything else plays at 0 (full slider level).
const MUSIC_TRIM_DB := {
	"music_world": -8.0,   # Wanderville_Background.mp3 was drowning out SFX
}

## Per-sound boost in dB, relative to the SFX slider. The farming set is mixed
## quiet in the source files, so they need a large lift to be heard over
## everything else; +10 dB is roughly 3x louder.
const SFX_TRIM_DB := {
	"till": 10.0,
	"plant": 10.0,
	"water_crop": 10.0,
	"harvest": 10.0,
	"collect_water": 10.0,
}

## Some of the farming files are long ambient loops (Digging_soil.mp3 is 47 s,
## Watering_plants.mp3 29 s, Collecting_water.mp3 32 s) rather than one-shot
## blips, but the action itself is instant — one key press. Capping play() to
## this many seconds makes them sound like a short burst instead of playing
## in full every time the bar ticks up.
const SFX_MAX_DURATION := {
	"till": 1.0,
	"water_crop": 1.0,
	"collect_water": 1.0,
	"cut_wood": 3.0,   # the wood floats for 3 s after a tree is cut
}

var music_volume: float = 80.0
var sfx_volume: float = 80.0
var music_muted := false

var _music: AudioStreamPlayer
var _music_key := ""
var _music_tween: Tween
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _loops: Dictionary = {}    ## key -> AudioStreamPlayer
var _cache: Dictionary = {}    ## key -> AudioStream
var _music_bus := 0
var _sfx_bus := 0
var _last_hover := -1.0


func _ready() -> void:
	# The fishing mini game pauses the tree, and a paused node's sound stops.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_music_bus = _ensure_bus("Music")
	_sfx_bus = _ensure_bus("SFX")

	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	_music.bus = "Music"
	add_child(_music)

	for i in SFX_VOICES:
		var voice := AudioStreamPlayer.new()
		voice.name = "SFX%d" % i
		voice.bus = "SFX"
		add_child(voice)
		_voices.append(voice)

	_load_settings()

	# Catches every button the game ever builds, including the ones created in
	# code after this point.
	get_tree().node_added.connect(_wire_button)
	for node in get_tree().root.find_children("*", "BaseButton", true, false):
		_wire_button(node)

	# current_scene is still null while autoloads start up.
	_start_scene_music.call_deferred()


func _ensure_bus(bus_name: String) -> int:
	var index := AudioServer.get_bus_index(bus_name)
	if index != -1:
		return index
	index = AudioServer.bus_count
	AudioServer.add_bus(index)
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, "Master")
	return index


# ── volume (same API the settings overlay and GameState already call) ────────

func set_music_volume(percent: float) -> void:
	music_volume = clampf(percent, 0.0, 100.0)
	AudioServer.set_bus_volume_db(_music_bus, _percent_to_db(music_volume))
	AudioServer.set_bus_mute(_music_bus, music_muted or music_volume <= 0.0)
	_save_settings()


func set_sfx_volume(percent: float) -> void:
	sfx_volume = clampf(percent, 0.0, 100.0)
	AudioServer.set_bus_volume_db(_sfx_bus, _percent_to_db(sfx_volume))
	AudioServer.set_bus_mute(_sfx_bus, sfx_volume <= 0.0)
	_save_settings()


# ── one-shot effects ────────────────────────────────────────────────────────

## pitch_jitter > 0 detunes each play a little, so a sound that fires often
## (footsteps, clicks) does not sound like the same sample on repeat.
func play(sound: Variant, pitch_jitter := 0.0) -> AudioStreamPlayer:
	var stream := _resolve(sound)
	if stream == null:
		return null
	var voice := _free_voice()
	voice.stream = stream
	voice.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	voice.volume_db = SFX_TRIM_DB.get(sound, 0.0) if sound is String else 0.0
	voice.play()
	var cap: float = SFX_MAX_DURATION.get(sound, 0.0) if sound is String else 0.0
	if cap > 0.0:
		var my_stream := stream
		get_tree().create_timer(cap, true, false, true).timeout.connect(func() -> void:
			if is_instance_valid(voice) and voice.playing and voice.stream == my_stream:
				voice.stop())
	return voice


## Kept for older call sites; play() is the name to use.
func play_sfx(sound: Variant) -> AudioStreamPlayer:
	return play(sound)


func _free_voice() -> AudioStreamPlayer:
	for voice in _voices:
		if not voice.playing:
			return voice
	# Everything is busy: reuse them in order so the same voice is not always
	# the one that gets cut off.
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	return voice


# ── looping effects (walking, mini game music, ambience) ────────────────────

func start_loop(key: String, volume_db := 0.0) -> void:
	var player: AudioStreamPlayer = _loops.get(key)
	if player == null:
		var stream := _looped(_resolve(key))
		if stream == null:
			return
		player = AudioStreamPlayer.new()
		player.name = "Loop_" + key
		player.bus = "SFX"
		player.stream = stream
		add_child(player)
		_loops[key] = player
	player.volume_db = volume_db
	if not player.playing:
		player.play()


func stop_loop(key: String) -> void:
	var player: AudioStreamPlayer = _loops.get(key)
	if player != null and player.playing:
		player.stop()


func is_looping(key: String) -> bool:
	var player: AudioStreamPlayer = _loops.get(key)
	return player != null and player.playing


func stop_all_loops() -> void:
	for player in _loops.values():
		player.stop()


# ── music ───────────────────────────────────────────────────────────────────

func play_music(sound: Variant, fade := MUSIC_FADE) -> void:
	var key: String = sound if sound is String else ""
	if key != "" and key == _music_key and _music.playing:
		return   # already playing this track: let it keep going across scenes
	var stream := _looped(_resolve(sound))
	if stream == null:
		stop_music(fade)
		return
	_music_key = key
	var target_db: float = MUSIC_TRIM_DB.get(key, 0.0)
	_kill_music_tween()
	if _music.playing and fade > 0.0:
		_music_tween = create_tween()
		_music_tween.tween_property(_music, "volume_db", -40.0, fade * 0.5)
		_music_tween.tween_callback(func() -> void:
			_music.stream = stream
			_music.play())
		_music_tween.tween_property(_music, "volume_db", target_db, fade * 0.5)
	else:
		_music.volume_db = target_db
		_music.stream = stream
		_music.play()


func stop_music(fade := 0.0) -> void:
	_music_key = ""
	_kill_music_tween()
	if not _music.playing or fade <= 0.0:
		_music.stop()
		_music.volume_db = 0.0
		return
	_music_tween = create_tween()
	_music_tween.tween_property(_music, "volume_db", -40.0, fade)
	_music_tween.tween_callback(func() -> void:
		_music.stop()
		_music.volume_db = 0.0)


## Used by the fishing mini game, which brings its own looping track.
func pause_music() -> void:
	if _music.playing:
		_music.stream_paused = true


func resume_music() -> void:
	_music.stream_paused = false


## Called by SceneManager on every scene change.
func music_for_scene(scene_path: String) -> void:
	stop_all_loops()   # footsteps and ambience never outlive their scene
	play_music(SCENE_MUSIC.get(scene_path, DEFAULT_MUSIC))


func _start_scene_music() -> void:
	var scene := get_tree().current_scene
	music_for_scene(scene.scene_file_path if scene != null else "")


func _kill_music_tween() -> void:
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()


# ── quitting ────────────────────────────────────────────────────────────────

## get_tree().quit() tears the window down before a sound can be heard, so the
## exit jingle is played first and the quit waits for it.
func quit_game() -> void:
	stop_all_loops()
	stop_music(0.2)
	var voice := play("game_exit")
	var wait := 0.9
	if voice != null and voice.stream != null:
		wait = minf(voice.stream.get_length(), QUIT_SOUND_MAX)
	await get_tree().create_timer(wait, true, false, true).timeout
	get_tree().quit()


# ── streams ─────────────────────────────────────────────────────────────────

func _resolve(sound: Variant) -> AudioStream:
	if sound is AudioStream:
		return sound
	var key := str(sound)
	if key == "":
		return null
	if _cache.has(key):
		return _cache[key]
	if not SOUNDS.has(key):
		push_warning("AudioManager: unknown sound key '%s'" % key)
		return null
	var path: String = SOUND_DIR + SOUNDS[key]
	if not ResourceLoader.exists(path):
		# Usually means the editor has not imported Assets/sounds yet.
		push_warning("AudioManager: missing audio file '%s'" % path)
		return null
	var stream := load(path) as AudioStream
	_cache[key] = stream
	return stream


## A copy of the stream with looping switched on — the import settings are left
## alone so the same file can also be used as a one-shot.
func _looped(stream: AudioStream) -> AudioStream:
	if stream == null:
		return null
	var copy := stream.duplicate() as AudioStream
	if copy is AudioStreamMP3 or copy is AudioStreamOggVorbis:
		copy.loop = true
	elif copy is AudioStreamWAV:
		copy.loop_mode = AudioStreamWAV.LOOP_FORWARD
	return copy


# ── buttons ─────────────────────────────────────────────────────────────────

func _wire_button(node: Node) -> void:
	var button := node as BaseButton
	if button == null or button.has_meta(&"silent") or button.has_meta(&"ui_sound"):
		return
	button.set_meta(&"ui_sound", true)
	button.mouse_entered.connect(func() -> void:
		if not button.disabled:
			_hover())
	button.pressed.connect(func() -> void: play("button_click"))


## Dragging the mouse across a grid of item buttons fires mouse_entered many
## times a second; without the gap that turns into a rattle.
func _hover() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_hover < HOVER_GAP:
		return
	_last_hover = now
	play("button_hover")


# ── settings file ───────────────────────────────────────────────────────────

func set_music_muted(value: bool) -> void:
	music_muted = value
	AudioServer.set_bus_mute(_music_bus, music_muted or music_volume <= 0.0)
	_save_settings()


func _percent_to_db(percent: float) -> float:
	if percent <= 0.0:
		return -80.0
	return linear_to_db(percent / 100.0)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("audio", "music_muted", music_muted)
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
	music_muted = bool(cfg.get_value("audio", "music_muted", false))
	set_music_volume(music_volume)
	set_sfx_volume(sfx_volume)
