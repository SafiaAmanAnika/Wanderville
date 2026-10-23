extends "res://Scripts/lobby_player_spawner.gd"

const DATA := "res://Assets/marketplace/placement.json"
const BG := preload("res://Assets/marketplace/background.png")

var _spec: Dictionary = {}
var _shops: Array[Dictionary] = []      # {sprite, id, owner, kind}
var _near: Dictionary = {}              # the shop you're standing in front of


func _ready() -> void:
	_spec = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	_build_background()
	_place_shop("supershop", 0.0, "supershop", "General Store")
	super._ready()

func _build_background() -> void:
	var period: float = _spec["background"]["period_x"]
	for i in range(-4, 5):
		var s := Sprite2D.new()
		s.texture = BG
		s.centered = false
		s.offset = Vector2(0, -512 + 408)    # bottom of the image at the walk line
		s.position = Vector2(i * period - period * 0.5, 0)
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.z_index = -10
		$Background.add_child(s)
		
func _place_shop(option_id: String, x: float, kind: String, label_text: String) -> void:
	var entry: Dictionary = {}
	for shop in _spec["shops"]:
		if shop["id"] == option_id:
			entry = shop
			break
	if entry.is_empty():
		return
	var sprite := Sprite2D.new()
	sprite.texture = load("res://Assets/marketplace/" + str(entry["file"]))
	sprite.centered = false
	sprite.offset = -Vector2(entry["anchor"][0], entry["anchor"][1])
	sprite.position = Vector2(x, _spec["scene"]["shop_baseline_y"])
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	$Shops.add_child(sprite)
	_add_name_label(sprite, entry, label_text)
	_shops.append({"sprite": sprite, "id": option_id, "kind": kind, "x": x})

func _add_name_label(sprite: Sprite2D, entry: Dictionary, text: String) -> void:
	var r: Array = entry["name_text_rect"]        # [x, y, w, h] in image pixels
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", WoodPanel.PIXEL_FONT)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color("40291f"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(r[0], r[1]) + sprite.offset
	label.size = Vector2(r[2], r[3])
	sprite.add_child(label)

func _process(_delta: float) -> void:
	if player == null:
		return
	# keep the player in the walkable band
	var band: Array = _spec["scene"]["walkable_y_range"]
	player.global_position.y = clampf(player.global_position.y, band[0], band[1])

	_near = {}
	for shop in _shops:
		if absf(player.global_position.x - shop["x"]) < 140.0:
			_near = shop
			break
	# tint the one you're in front of so it reads as clickable
	for shop in _shops:
		shop["sprite"].modulate = Color(1.15, 1.15, 1.1) if shop == _near else Color.WHITE


func _unhandled_input(event: InputEvent) -> void:
	if _near.is_empty():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var sprite: Sprite2D = _near["sprite"]
		if sprite.get_rect().has_point(sprite.to_local(get_global_mouse_position())):
			get_viewport().set_input_as_handled()
			_open(_near)
			
func _open(shop: Dictionary) -> void:
	match shop["kind"]:
		"supershop":
			var menu = preload("res://Scripts/inventory/storage_menu.gd").new()
			get_tree().current_scene.add_child(menu)
		"own":  pass      # Phase 2
		"friend": pass    # Phase 3
		
func _fit_camera() -> void:
	camera.zoom = Vector2.ONE * _preferred_zoom
	
