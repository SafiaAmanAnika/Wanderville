extends CharacterBody2D
## Local visual companion: bounded sensing, purposeful exploration and rest.
enum State { IDLE, FOLLOW, ROAM, SLEEP }
const DIRECTIONS := ["n","ne","e","se","s","sw","w","nw"]
const CODES := ["cat","dog","rabbit","fox","duck","red_panda"]
const MANIFEST := preload("res://Assets/Pets/pets_manifest.json")
const DETECT_RANGE := 750.0
const LOSE_RANGE := 900.0
const FOLLOW_START := 180.0
const FOLLOW_STOP := 110.0
const NEAR_ROAM_RADIUS := 280.0
const HOME_ROAM_RADIUS := 480.0
const WALK_SPEED := 125.0
const FOLLOW_SPEED := 340.0
const REST_AFTER := 32.0
const VISUAL_SCALE := 0.95
var species := "cat"
var owner_body: CharacterBody2D
var navigation: Node
var state := State.IDLE
var sprite: AnimatedSprite2D
var home := Vector2.ZERO
var target := Vector2.ZERO
var path := PackedVector2Array()
var visited: Dictionary = {}
var rng := RandomNumberGenerator.new()
var facing := "s"
var state_time := 0.0
var active_time := 0.0
var pause_time := 2.0
var sleep_time := 20.0
var repath_time := 0.0
var stuck_time := 0.0
var collision_events := 0
var previous_direction := Vector2.DOWN
var owner_visible := true
var sleep_texture: Texture2D
var sleep_scale := 0.2375
var sleep_offset := Vector2(0,-44)
var _last_owner_position := Vector2.ZERO
var _time := 0.0
static var _frames: Dictionary = {}

func _ready() -> void:
	rng.randomize()
	motion_mode=CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer=4
	collision_mask=1|4
	z_index=2
	add_to_group("pet_companions")
	var collider := CollisionShape2D.new()
	collider.name="FootCollision"
	var circle := CircleShape2D.new(); circle.radius=18
	collider.shape=circle; add_child(collider)
	sprite=AnimatedSprite2D.new(); sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	set_species(species)
	home=global_position; target=home
	if is_instance_valid(owner_body): _last_owner_position=owner_body.global_position

static func frames_for(code: String) -> SpriteFrames:
	if _frames.has(code): return _frames[code]
	var frames := SpriteFrames.new(); frames.remove_animation("default")
	for entry in MANIFEST.data.pets:
		if entry.id != code: continue
		var texture: Texture2D = load("res://Assets/Pets/"+str(entry.sheet))
		for row in range(8):
			var animation: String = "walk_"+str(DIRECTIONS[row])
			frames.add_animation(animation); frames.set_animation_speed(animation,8)
			for column in range(8):
				var frame := AtlasTexture.new(); frame.atlas=texture
				frame.region=Rect2(column*128,row*128,128,128)
				frames.add_frame(animation,frame)
	_frames[code]=frames
	return frames

func set_species(code: String) -> void:
	species=code if code in CODES else "cat"
	if sprite==null: return
	sprite.sprite_frames=frames_for(species)
	sleep_texture=null
	var sleep_path := "res://Assets/Pets/generated/sleep_atlas.png"
	if ResourceLoader.exists(sleep_path):
		var sheet: Texture2D=load(sleep_path)
		var frame := AtlasTexture.new(); frame.atlas=sheet
		var cell := sheet.get_size()/Vector2(3,2)
		var index := CODES.find(species)
		# Sleep atlas order follows the asset brief: cat, dog, rabbit / fox, duck, panda.
		frame.region=Rect2(Vector2(index%3,index/3)*cell,cell)
		sleep_texture=frame
		var metadata_path := "res://Assets/Pets/generated/sleep_frames.json"
		if FileAccess.file_exists(metadata_path):
			var metadata: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
			var bounds: Array=metadata[species]
			sleep_scale=VISUAL_SCALE*100.0/float(bounds[2]-bounds[0])
			sleep_offset=Vector2(cell.x*0.5-(float(bounds[0])+float(bounds[2]))*0.5,cell.y*0.5-float(bounds[3]))*sleep_scale
		if not sprite.sprite_frames.has_animation("sleep"):
			sprite.sprite_frames.add_animation("sleep")
			sprite.sprite_frames.add_frame("sleep",frame)
	_animate(Vector2.ZERO)

func _physics_process(delta: float) -> void:
	if navigation==null or not navigation.ready_for_paths or not is_instance_valid(owner_body): return
	_time+=delta; state_time+=delta; repath_time-=delta
	var distance := global_position.distance_to(owner_body.global_position)
	var owner_moved := owner_body.global_position.distance_to(_last_owner_position)>20
	_last_owner_position=owner_body.global_position
	var previously_visible := owner_visible
	owner_visible=distance <= (LOSE_RANGE if owner_visible else DETECT_RANGE)
	if previously_visible and not owner_visible: home=global_position
	if state==State.SLEEP:
		velocity=Vector2.ZERO
		_animate(Vector2.ZERO); queue_redraw()
		if state_time>=sleep_time or (owner_visible and (distance>FOLLOW_START or owner_moved)):
			active_time=0; _set_state(State.IDLE)
		return
	active_time+=delta
	if owner_visible and (distance>FOLLOW_START or (state==State.FOLLOW and distance>FOLLOW_STOP)):
		if state!=State.FOLLOW: _set_state(State.FOLLOW)
		if repath_time<=0:
			var behind := (global_position-owner_body.global_position).normalized()
			_set_target(owner_body.global_position+behind*FOLLOW_STOP)
			repath_time=0.55
	elif state==State.FOLLOW:
		home=global_position; _set_state(State.IDLE)
	if state==State.IDLE:
		velocity=Vector2.ZERO
		if state_time>=pause_time:
			if active_time>=REST_AFTER:
				sleep_time=rng.randf_range(16,26); _set_state(State.SLEEP)
			else:
				_choose_roam()
	if state==State.ROAM and path.is_empty(): _set_state(State.IDLE)
	var before := global_position
	if state in [State.FOLLOW,State.ROAM]: _move_path(delta)
	else: velocity=Vector2.ZERO
	if velocity.length()>5 and global_position.distance_to(before)<velocity.length()*delta*0.15:
		stuck_time+=delta
	else: stuck_time=0
	if stuck_time>1.1:
		if not path.is_empty(): navigation.mark_blocked(path[0])
		stuck_time=0; path.clear(); repath_time=0
		if state==State.ROAM: _set_state(State.IDLE)
	_animate(global_position-before)

func _set_state(next: int) -> void:
	state=next; state_time=0; path.clear(); velocity=Vector2.ZERO
	if next==State.IDLE: pause_time=rng.randf_range(1.5,3.5)
	queue_redraw()

func _set_target(point: Vector2) -> void:
	target=point; path=navigation.path(global_position,point)
	if path.size()>1 and navigation.cell_of(global_position)==navigation.cell_of(path[0]): path.remove_at(0)
	while not path.is_empty() and global_position.distance_to(path[0])<22: path.remove_at(0)

func _choose_roam() -> void:
	var anchor := owner_body.global_position if owner_visible else home
	var leash := NEAR_ROAM_RADIUS if owner_visible else HOME_ROAM_RADIUS
	var best := Vector2.INF
	var best_score := -INF
	for attempt in range(18):
		var angle := rng.randf_range(0,TAU)
		var candidate: Vector2 = navigation.nearest(anchor+Vector2.RIGHT.rotated(angle)*rng.randf_range(90,leash))
		if not candidate.is_finite() or candidate.distance_to(anchor)>leash: continue
		var step := candidate-global_position
		if step.length()<65: continue
		var novelty := 1.0/(1.0+float(visited.get(navigation.cell_of(candidate),0)))
		var heading := previous_direction.dot(step.normalized())
		var clearance := 0.0
		for direction in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
			if navigation.clear(candidate+direction*45): clearance+=0.25
		var comfort := 1.0-absf(candidate.distance_to(anchor)-180)/leash
		var score := novelty*3.0+clearance*2.0+comfort+heading*0.5+rng.randf()*0.25
		if score>best_score:
			var route: PackedVector2Array=navigation.path(global_position,candidate)
			if route.is_empty(): continue
			best=candidate; best_score=score
	if not best.is_finite():
		pause_time=1.5; state_time=0; return
	_set_state(State.ROAM); _set_target(best)
	var key: Vector2i=navigation.cell_of(best)
	visited[key]=int(visited.get(key,0))+1
	# Bounded memory prevents a long session from growing the exploration history.
	if visited.size()>64: visited.erase(visited.keys()[0])

func _move_path(delta: float) -> void:
	while not path.is_empty() and global_position.distance_to(path[0])<18: path.remove_at(0)
	if path.is_empty(): velocity=Vector2.ZERO; return
	var direction := global_position.direction_to(path[0])
	previous_direction=direction
	var speed := FOLLOW_SPEED if state==State.FOLLOW else WALK_SPEED
	velocity=direction*minf(speed,global_position.distance_to(path[0])/delta)
	move_and_slide()
	collision_events+=get_slide_collision_count()
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		var body := hit.get_collider() as StaticBody2D
		if body==null: continue
		var shape_owner := body.shape_find_owner(hit.get_collider_shape_index())
		var obstruction := body.shape_owner_get_owner(shape_owner) as Node2D
		if obstruction!=null:
			navigation.block_shape(obstruction)
			path.clear(); repath_time=0
			if state==State.ROAM: _set_state(State.IDLE)
			break

func _animate(movement: Vector2) -> void:
	if sprite==null: return
	if movement.length()>0.05:
		var index := posmod(roundi((movement.angle()+PI*0.5)/(PI*0.25)),8)
		facing=DIRECTIONS[index]
	if state==State.SLEEP and sleep_texture!=null:
		if sprite.animation!="sleep": sprite.play("sleep")
		var breath := 1.0+sin(_time*2.2)*0.015
		sprite.scale=Vector2.ONE*sleep_scale*breath
		sprite.position=sleep_offset*breath
	else:
		sprite.scale=Vector2.ONE*VISUAL_SCALE; sprite.position=Vector2(0,-46*VISUAL_SCALE)
		var animation := "walk_"+facing
		if sprite.animation!=animation: sprite.play(animation)
		if movement.length()>0.05:
			if not sprite.is_playing(): sprite.play()
		else: sprite.stop(); sprite.frame=0

func _draw() -> void:
	# Tiny animated sleep bubbles remain code-drawn so they stay sharp in-game.
	if state!=State.SLEEP: return
	for i in range(3):
		var phase := fmod(_time*0.35+float(i)/3.0,1.0)
		var p := Vector2(26+phase*18,-65-phase*36)
		var ink := Color(1,0.96,0.84,1-phase)
		var width := 7.0+phase*5
		draw_polyline(PackedVector2Array([p,p+Vector2(width,0),p+Vector2(0,width),p+Vector2(width,width)]),ink,2)
