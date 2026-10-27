extends Label
## Compact wooden overhead namecard shared by local and remote players.
const Style = preload("res://Scripts/ui/lobby_theme.gd")
const BOARD := preload("res://Assets/ui/images/shared/button_normal.webp")
var local_identity := false
var follow_body := false
var _wood: Node2D
var _head := Vector2(0, -130)

static func attach(body: Node2D, title: String = "", local: bool = false) -> Label:
	var existing := body.get_node_or_null("PlayerNamecard")
	if existing != null: return existing
	var card := new()
	card.name = "PlayerNamecard"
	card.text = title
	card.local_identity = local
	card.follow_body = true
	body.add_child(card)
	return card

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_theme_font_override("font", Style.body_font())
	add_theme_font_size_override("font_size", 16)
	add_theme_color_override("font_color", Color("382820"))
	add_theme_color_override("font_shadow_color", Color("f5e7d3"))
	add_theme_constant_override("shadow_offset_y", 1)
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	clip_text = true
	z_index = 20
	if follow_body:
		for child in get_parent().get_children():
			if child is AnimatedSprite2D and child.sprite_frames != null:
				var tex: Texture2D = child.sprite_frames.get_frame_texture(child.animation, 0)
				if tex != null:
					var bounds := tex.get_image().get_used_rect()
					_head = child.position + Vector2(0, bounds.position.y - tex.get_height() * 0.5) * child.scale
				break
	_wood = Node2D.new()
	_wood.show_behind_parent = true
	add_child(_wood)
	_wood.draw.connect(_draw_wood)
	_update_card()

func _process(_delta: float) -> void:
	_update_card()

func _update_card() -> void:
	if local_identity:
		text = Global.display_name.strip_edges()
		if text.is_empty(): text = Global.username.strip_edges()
		if text.is_empty(): text = "Player"
		visible = GameState.is_visiting() or get_parent().get_parent().has_signal("player_spawned")
	var width := clampf(get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 44, 128, 240)
	size = Vector2(width, 32)
	if follow_body:
		var body := get_parent() as Node2D
		scale = Vector2.ONE / body.global_scale.abs().max(Vector2(0.001, 0.001))
		position = _head + Vector2(-width * 0.5, -42) * scale
	else:
		position.x = -width * 0.5
	if _wood != null: _wood.queue_redraw()

func _draw_wood() -> void:
	_wood.draw_texture_rect(BOARD, Rect2(Vector2(-8, -7), size + Vector2(16, 14)), false)
