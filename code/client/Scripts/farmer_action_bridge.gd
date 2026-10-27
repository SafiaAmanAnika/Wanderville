extends Node
## Observe successful local farm changes; Zenia's farm_controller stays untouched.
## A click creates one candidate. Only the corresponding committed state change
## plays a tool, so denied/too-far/no-water requests and server refreshes stay quiet.
var _farm: Node
var _player: CharacterBody2D
var _pending: Dictionary = {}

func _ready() -> void:
	_player=get_parent() as CharacterBody2D
	var scene := get_tree().current_scene
	if scene != null: _farm=scene.find_child("FarmController",true,false)
	if _farm == null: set_process(false); set_process_input(false)

func _input(event: InputEvent) -> void:
	if _farm == null: return
	if not (event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT): return
	if _farm._blocked() or _farm._dragging: return
	var tile: Vector2i=_farm._hover_tile()
	if not _farm._is_in_farm_area(tile) or not _farm._in_reach(tile): return
	if _player._busy or _player.fishing:
		get_viewport().set_input_as_handled(); return
	if not _pending.is_empty(): return
	var key: String=_farm._key(tile)
	var crop: Dictionary=_farm.active_crops.get(key,{})
	var action := ""
	if not _farm.tilled_tiles.has(key): action="hoe"
	elif not crop.is_empty():
		if int(crop.stage)>=_farm.GROWTH_STAGES: action="scythe"
		elif not bool(crop.watered): action="water"
	if action.is_empty(): return
	_pending={"key":key,"action":action,"tile":tile,"expires":Time.get_ticks_msec()+15000}

func _process(_delta: float) -> void:
	if _pending.is_empty(): return
	var key: String=_pending.key
	var crop: Dictionary=_farm.active_crops.get(key,{})
	var committed: bool=(_pending.action=="hoe" and _farm.tilled_tiles.has(key)) \
		or (_pending.action=="water" and bool(crop.get("watered",false))) \
		or (_pending.action=="scythe" and crop.is_empty())
	if committed:
		var action: String=_pending.action
		var target: Vector2=_farm._tile_to_world(_pending.tile)-_player.global_position
		if not target.is_zero_approx(): _player.facing=_player._dir_from_vector(target)
		_pending={}; _player.play_action(action)
	elif Time.get_ticks_msec()>int(_pending.expires) or (not _farm._backend_busy and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)):
		_pending={}
