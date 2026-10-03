extends Control

const BG_TEXTURE := preload("res://Assets/background/bg.png")
const PIXEL_FONT := preload("res://Assets/fonts/BoldPixels.ttf")

const TEXT_COLOR := Color(0.95, 0.91, 0.80)
const TEXT_SECONDARY := Color(0.82, 0.74, 0.58)
const GOLDEN := Color(1.0, 0.84, 0.0)

const CREATE_WORLD_LABEL := "+ Create New World"

@onready var _bg: TextureRect = %Background
@onready var _grid: GridContainer = %WorldGrid
@onready var _enter_button: WoodButton = %EnterWorldButton
@onready var _back_button: WoodButton = %BackButton
@onready var _status_label: Label = %StatusLabel
@onready var _subtitle: Label = %Subtitle
@onready var _info_panel: PanelContainer = %InfoPanel
@onready var _info_label: Label = %InfoPanel/InfoLabel

var _selected_world_id: String = ""
var _selected_world_data: Dictionary = {}
var _world_card_scene: PackedScene = preload("res://Scenes/components/WorldCard.tscn")
var _worlds: Array[Dictionary] = []


func _ready() -> void:
	_bg.texture = BG_TEXTURE

	WoodPanel.apply_panel_title_style(%Title)
	WoodPanel.apply_subtitle_style(_subtitle)
	WoodPanel.apply_status_label(_status_label)
	_apply_info_panel_style()
	_apply_info_label_style()

	_info_panel.visible = false

	_enter_button.pressed.connect(_on_enter_world)
	_back_button.pressed.connect(_on_back)

	_fetch_worlds()
	WoodPanel.play_entrance(%FormPanel)


func _apply_info_panel_style() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = WoodPanel.PARCHMENT_BG
	sb.border_color = WoodPanel.PARCHMENT_DARK
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	_info_panel.add_theme_stylebox_override("panel", sb)


func _apply_info_label_style() -> void:
	_info_label.add_theme_font_override("font", PIXEL_FONT)
	_info_label.add_theme_font_size_override("font_size", WoodPanel.SIZE_SMALL)
	_info_label.add_theme_color_override("font_color", Color(0.30, 0.22, 0.12))
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT


func _fetch_worlds() -> void:
	_status_label.text = "Loading worlds..."

	var res := await APIClient.get_my_world(Global.token)

	if not is_instance_valid(self):
		return

	if not bool(res.get("ok", false)):
		var body = res.get("body", {})
		var msg := "Failed to load worlds."
		if typeof(body) == TYPE_DICTIONARY:
			msg = str(body.get("message", msg))
		_status_label.text = msg
		return

	_status_label.text = ""

	var body = res.get("body", {})
	if typeof(body) != TYPE_DICTIONARY:
		body = {}
	var data = body.get("data", {})
	if typeof(data) != TYPE_DICTIONARY:
		data = {}
	var worlds: Array[Dictionary] = []
	if data.has("id"):
		worlds = [data]

	_worlds = worlds

	for child in _grid.get_children():
		child.queue_free()

	if worlds.is_empty():
		_status_label.text = "No worlds found. Create one to get started!"
		_add_create_world_card()
		return

	for w in worlds:
		var card := _world_card_scene.instantiate()
		_grid.add_child(card)
		card.set_world(
			str(w.get("id", "")),
			str(w.get("name", "Unnamed World")),
			null,
			w
		)
		card.pressed.connect(_on_world_clicked.bind(w, card))

	_add_create_world_card()

	if worlds.size() == 1:
		var only_card = _grid.get_child(0)
		_select_world(worlds[0], only_card)


func _add_create_world_card() -> void:
	var btn := Button.new()
	btn.text = CREATE_WORLD_LABEL
	btn.custom_minimum_size = Vector2(280, 180)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.45, 0.35, 0.22, 0.6)
	sb.border_color = WoodPanel.WOOD_BORDER
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	btn.add_theme_stylebox_override("normal", sb)

	var hover_sb := sb.duplicate()
	hover_sb.bg_color = WoodPanel.WOOD_HOVER
	hover_sb.border_color = WoodPanel.WOOD_BEVEL_LIGHT
	btn.add_theme_stylebox_override("hover", hover_sb)

	var pressed_sb := sb.duplicate()
	pressed_sb.bg_color = WoodPanel.WOOD_DARK
	btn.add_theme_stylebox_override("pressed", pressed_sb)

	btn.add_theme_font_override("font", PIXEL_FONT)
	btn.add_theme_font_size_override("font_size", WoodPanel.SIZE_BUTTON)
	btn.add_theme_color_override("font_color", TEXT_SECONDARY)
	btn.add_theme_color_override("font_hover_color", TEXT_COLOR)

	_grid.add_child(btn)
	btn.pressed.connect(_on_create_world)


func _on_world_clicked(world: Dictionary, card: Button) -> void:
	_select_world(world, card)


func _select_world(world: Dictionary, selected_card: Button) -> void:
	_selected_world_id = str(world.get("id", ""))
	_selected_world_data = world
	_enter_button.disabled = false

	for card in _grid.get_children():
		if card == selected_card:
			card.modulate = Color(1, 1, 1, 1)
			if card.has_method("set_selected"):
				card.set_selected(true)
		else:
			card.modulate = Color(0.7, 0.7, 0.7, 0.7)
			if card.has_method("set_selected"):
				card.set_selected(false)

	_show_world_info(world)


func _show_world_info(world: Dictionary) -> void:
	var lines: PackedStringArray = []
	var world_name := str(world.get("name", "Unnamed World"))
	lines.append("World: %s" % world_name)
	if world.has("created_at"):
		lines.append("Created: %s" % str(world["created_at"]))
	if world.has("season"):
		lines.append("Season: %s" % str(world["season"]))
	if world.has("day"):
		lines.append("Day: %s" % str(world["day"]))
	if world.has("play_time"):
		lines.append("Played: %s" % str(world["play_time"]))
	if world.has("population"):
		lines.append("Population: %s" % str(world["population"]))

	_info_label.text = "   ".join(lines)
	_info_panel.visible = true

	var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_info_panel.modulate.a = 0.0
	tw.tween_property(_info_panel, "modulate:a", 1.0, 0.25)


func _on_enter_world() -> void:
	if _selected_world_id == "":
		return
	_enter_button.disabled = true
	var response: Dictionary = await APIClient.update_profile({"map_code": "campus"})
	_enter_button.disabled = false
	if not bool(response.get("ok", false)):
		_status_label.text = APIClient.error_text(response)
		return
	Global.selected_world_id = _selected_world_id
	Global.save_session()
	SceneManager.goto_world()


func _on_back() -> void:
	SceneManager.goto_map_selection()


func _on_create_world() -> void:
	SceneManager.goto_map_selection()
