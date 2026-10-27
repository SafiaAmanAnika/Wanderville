extends Node2D

@onready var sprite: Sprite2D = $Sprite2D

enum State { EMPTY, TILLED, WATERED, PLANTED, HARVESTABLE }
var state: State = State.EMPTY
var crop_type: String = ""
var growth_stage: int = 0
var is_watered: bool = false
var growth_timer: float = 0.0

func till():
	if state == State.EMPTY:
		state = State.TILLED
		sprite.modulate = Color(0.8, 0.6, 0.4)
		return true
	return false

func water():
	if state == State.TILLED or state == State.PLANTED:
		state = State.WATERED
		is_watered = true
		sprite.modulate = Color(0.6, 0.5, 0.3)
		return true
	return false

func plant(seed: String) -> bool:
	if state != State.TILLED and state != State.WATERED:
		return false
	state = State.PLANTED
	crop_type = seed
	growth_stage = 0
	_spawn_crop()
	return true

func _spawn_crop():
	var crop = Sprite2D.new()
	crop.name = "Crop"
	crop.position = Vector2(0, -20)

	var path = "res://Assets/farming/regular_crops/%s_spritesheet.png" % crop_type
	if crop_type == "paddy":
		path = "res://Assets/farming/regular_crops/paddy_spritesheet.png"

	if ResourceLoader.exists(path):
		crop.texture = load(path)
		crop.region_enabled = true
		crop.region_rect = Rect2(0, 0, 32, 32)
		crop.scale = Vector2(2, 2)
	else:
		var rect = ColorRect.new()
		rect.size = Vector2(24, 24)
		rect.position = Vector2(-12, -12)
		rect.color = _crop_color(crop_type)
		crop.add_child(rect)

	add_child(crop)

func _crop_color(crop_type: String) -> Color:
	match crop_type:
		"wheat":  return Color(0.95, 0.85, 0.4)
		"paddy":  return Color(0.7, 0.85, 0.4)
		_:        return Color(0.6, 0.8, 0.4)

func _process(delta):
	if state == State.PLANTED and is_watered:
		growth_timer += delta
		if growth_timer >= 5.0:
			growth_timer = 0.0
			growth_stage += 1
			if growth_stage >= 3:
				state = State.HARVESTABLE
			_update_crop_visual()

func _update_crop_visual():
	var crop = get_node_or_null("Crop")
	if crop and crop is Sprite2D and crop.texture:
		var frame_w = crop.texture.get_width() / 4
		crop.region_rect = Rect2(growth_stage * frame_w, 0, frame_w, 32)

func harvest() -> String:
	if state != State.HARVESTABLE:
		return ""
	var harvested = crop_type
	state = State.TILLED
	is_watered = false
	crop_type = ""
	growth_stage = 0
	growth_timer = 0.0
	sprite.modulate = Color(0.8, 0.6, 0.4)
	var crop = get_node_or_null("Crop")
	if crop:
		crop.queue_free()
	return harvested
	
func _ready():
	# Make it HUGE and bright so we can see it
	sprite.scale = Vector2(4, 4)
	sprite.modulate = Color(1, 0, 0, 1)  # Bright red
