extends SceneTree
## Real world, physics, A* navigation, species selector and generated sleep art.
var failures := 0
var output := "res://../../test-output/pets"
class CollisionBridge:
	extends Node
	var current_phase := "admitted"
	func phase() -> String: return current_phase

func _initialize() -> void: call_deferred("run")
func check(value: bool,message: String) -> void:
	print("PET_CHECK ",message," PASS" if value else " FAIL")
	if not value: failures+=1
func wait_for(predicate: Callable,seconds: float=15) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		if predicate.call(): return true
		await create_timer(0.05).timeout
	return false
func shot(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name+".png"))

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size=Vector2i(1578,997)
	var session := root.get_node("Global"); session.clear_session(); session.selected_character="girl_a"
	root.get_node("APIClient").base_url="http://127.0.0.1:1/pet-companions-check"
	var world: Node=load("res://Scenes/world.tscn").instantiate(); root.add_child(world); current_scene=world
	var player: CharacterBody2D=world.get_node("girl"); player.set_physics_process(false)
	var pets: Node=world.get_node("Pets")
	check(await wait_for(func(): return is_instance_valid(pets.companion) and pets._loaded),"companion joins the real world on a navigable spawn")
	if not is_instance_valid(pets.companion): quit(1); return
	var pet: CharacterBody2D=pets.companion
	var nav: Node=pets.navigation
	check(nav.clear(pet.global_position),"spawn has body clearance from map walls")
	check(not pet.is_in_group("player") and get_nodes_in_group("pet_companions").size()==1,"one pet spawns without becoming a player")
	check(world.get_node_or_null("catto_og")==null,"old collision-free follower is replaced")
	pets.open_menu()
	check(pets.panel.visible and root.get_node("GameState").menu_open,"paw menu opens and gates player input")
	for code in pet.CODES:
		await pets.choose(code)
		check(pet.species==code,"selector equips "+code)
		var config := ConfigFile.new(); config.load("user://pet_companion.cfg")
		check(config.get_value("offline","species")==code,"offline selection persists for "+code)
		for direction in pet.DIRECTIONS:
			check(pet.sprite.sprite_frames.get_frame_count("walk_"+str(direction))==8,code+" walk "+str(direction)+" has eight frames")
		check(pet.sleep_texture!=null,"generated sleep pose is loaded for "+code)
		check(is_equal_approx(pet.visual_scale,pet.VISUAL_SCALE*float(pet.SPECIES_SIZE[code])),code+" uses its species size")
		check(is_equal_approx((pet.get_node("FootCollision").shape as CircleShape2D).radius,18.0*float(pet.SPECIES_SIZE[code])),code+" collider fits its size")
	await shot("pet-selector")
	pets.close_menu(); await pets.choose("cat")
	check(float(pet.SPECIES_SIZE.duck)<float(pet.SPECIES_SIZE.cat),"duck is smaller than cat")
	check(pet.WALK_SPEED==80 and pet.FOLLOW_SPEED==230,"roaming and following use slower speeds")
	check(pet.collision_mask & 2 != 0 and pet.z_index==0 and pets.y_sort_enabled,"pets detect multiplayer bodies and use world depth sorting")
	player.global_position=Vector2(3000,-550)
	pet.global_position=player.global_position+Vector2(250,65)
	pet.set_physics_process(false)
	await create_timer(0.05).timeout
	var player_hit: KinematicCollision2D=player.move_and_collide(Vector2(400,0))
	check(player_hit!=null and player_hit.get_collider()==pet,"player movement physically collides with the pet instead of passing through")
	pet.set_physics_process(true)
	var collision_bridge := CollisionBridge.new(); collision_bridge.name="EnetGameplayBridge"; world.add_child(collision_bridge)
	pets._update_owner_collision()
	check(not player.get_collision_mask_value(3),"server-controlled movement avoids local pet collision correction jitter")
	collision_bridge.current_phase="legacy"; pets._update_owner_collision()
	check(player.get_collision_mask_value(3),"local movement retains solid pet collision after network fallback")
	world.remove_child(collision_bridge); collision_bridge.free()
	player.global_position=Vector2(3300,-550)
	pet.global_position=pet._owner_center()+Vector2(-190,0)
	pet._set_state(pet.State.ROAM)
	pet.path=PackedVector2Array([pet._owner_center()+Vector2(190,0)])
	var steering: Vector2=pet._avoid_owner(Vector2.RIGHT)
	check(absf(steering.y)>0.5,"a route across the owner steers around their body")
	var chosen_side: float=pet._avoid_side
	pet._avoid_owner(Vector2(1,0.01).normalized())
	pet._avoid_owner(Vector2(1,-0.01).normalized())
	check(chosen_side!=0 and pet._avoid_side==chosen_side,"small owner avoidance changes retain the chosen passing side")
	pet.facing="e"
	pet._animate(Vector2.RIGHT.rotated(deg_to_rad(23)))
	pet._animate(Vector2.RIGHT.rotated(deg_to_rad(22)))
	check(pet.facing=="e","tiny heading changes at a direction boundary do not flicker animations")
	pet._animate(Vector2.RIGHT.rotated(deg_to_rad(35)))
	check(pet.facing=="se","a deliberate turn still changes animation direction")
	var minimum_space := INF
	for frame in range(120):
		await physics_frame
		minimum_space=minf(minimum_space,pet.global_position.distance_to(pet._owner_center()))
	check(minimum_space>=pet.OWNER_SPACE-3,"crossing route respects owner personal space over real physics frames")
	pet.global_position=pet._owner_center()+Vector2(-70,0)
	pet._set_state(pet.State.IDLE)
	await create_timer(0.8).timeout
	check(pet.global_position.distance_to(pet._owner_center())>=pet.OWNER_SPACE-3,"idle pet yields when the owner enters its space")
	await create_timer(0.4).timeout
	check(not pet._yielding and pet.velocity==Vector2.ZERO,"yielding clears a wider buffer and settles without repeated idle resets")
	check(not root.get_node("GameState").menu_open,"closing pet menu restores gameplay")
	player.global_position=Vector2(3300,-550); pet.global_position=Vector2(2850,-550)
	pet.home=pet.global_position; pet._set_state(pet.State.IDLE); pet.repath_time=0
	var camera: Camera2D=player.get_node("Camera2D"); camera.position_smoothing_enabled=false; camera.reset_smoothing()
	var start_distance := pet.global_position.distance_to(player.global_position)
	await create_timer(1.5).timeout
	check(pet.global_position.distance_to(player.global_position)<start_distance-150,"pet follows a nearby owner through real physics")
	check(pet.global_position.distance_to(player.global_position)>65,"following preserves personal space")
	await shot("following")
	player.global_position=Vector2(1900,500)
	await create_timer(0.1).timeout
	check(not pet.owner_visible and pet.state!=pet.State.FOLLOW,"outside proximity the pet stops chasing")
	pet.rng.seed=42; pet._choose_roam()
	check(pet.state==pet.State.ROAM and not pet.path.is_empty(),"heuristic roaming selects a reachable route")
	check(pet.target.distance_to(pet.home)<=pet.HOME_ROAM_RADIUS,"distant roaming stays within its familiar area")
	var valid := true
	for point in pet.path:
		if not nav.clear(point): valid=false
	check(valid,"roaming path avoids map obstacles with clearance")
	for i in range(5): pet._choose_roam()
	check(pet.visited.size()>2,"novelty scoring explores multiple destinations")
	pet._set_state(pet.State.IDLE); pet.active_time=60; pet.pause_time=0.01
	await create_timer(0.12).timeout
	check(pet.state==pet.State.ROAM and not pet.path.is_empty(),"after one minute away pet keeps choosing heuristic roaming routes instead of napping")
	pet._set_state(pet.State.IDLE)
	check(pet.pause_time<=1.0,"independent exploring has only short pauses between routes")
	pet.active_time=pet.REST_AFTER; pet.pause_time=0.01
	await create_timer(0.12).timeout
	check(pet.state==pet.State.SLEEP and pet.sprite.animation=="sleep","a tired pet settles into its generated sleep pose")
	var resting_position := pet.global_position
	await create_timer(0.25).timeout
	check(pet.global_position.distance_to(resting_position)<0.1,"sleeping pet stays grounded and stationary")
	check(pet.collision_layer!=0 and not pet.get_node("FootCollision").disabled,"sleep keeps its physics body active")
	pet.sleep_time=pet.state_time+0.05
	await create_timer(0.2).timeout
	check(not pet.owner_visible and pet.state==pet.State.ROAM and not pet.path.is_empty(),"pet wakes and resumes exploring while its owner is still away")
	check(pet.active_time<1,"waking gives the pet a fresh active period before another nap")
	pet._set_state(pet.State.SLEEP); pet.sleep_time=20
	player.global_position=pet.global_position+Vector2(300,0); camera.reset_smoothing()
	await create_timer(0.2).timeout
	check(pet.state==pet.State.FOLLOW,"sleeping pet wakes when its nearby owner leaves")
	# A dynamic obstacle is absent from the baked grid: actual physics must stop it.
	player.global_position=Vector2(3350,-550); pet.global_position=Vector2(2800,-550)
	pet._set_state(pet.State.IDLE); pet.repath_time=0; pet.owner_visible=true
	var wall := StaticBody2D.new(); wall.position=Vector2(2900,-550)-world.global_position
	var shape := CollisionShape2D.new(); var rectangle := RectangleShape2D.new(); rectangle.size=Vector2(20,300); shape.shape=rectangle
	wall.add_child(shape); world.add_child(wall)
	await create_timer(0.8).timeout
	check(pet.global_position.x<2876,"collision body cannot walk through an unbaked furniture obstacle")
	check(pet.collision_events>0,"wall collision is reported by the physics engine")
	await create_timer(7).timeout
	check(pet.global_position.distance_to(player.global_position)<220,"stuck recovery replans around the temporary obstruction")
	wall.queue_free()
	# Pose review: all six sleep sprites keep the same body-ground anchor.
	player.global_position=Vector2(1900,500); camera.global_position=pet.global_position
	pet._set_state(pet.State.SLEEP); pet.sleep_time=60
	for code in pet.CODES:
		pet.set_species(code); await create_timer(0.05).timeout; await shot("sleep-"+str(code))
	world.queue_free(); await process_frame
	print("PET_RESULT failures=",failures)
	quit(1 if failures else 0)
