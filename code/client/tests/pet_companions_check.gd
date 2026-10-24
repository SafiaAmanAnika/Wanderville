extends SceneTree
## Real world, physics, A* navigation, species selector and generated sleep art.
var failures := 0
var output := "res://../../test-output/pets"

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
	await shot("pet-selector")
	pets.close_menu(); await pets.choose("cat")
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
	pet._set_state(pet.State.IDLE); pet.active_time=pet.REST_AFTER; pet.pause_time=0.01
	await create_timer(0.12).timeout
	check(pet.state==pet.State.SLEEP and pet.sprite.animation=="sleep","a tired pet settles into its generated sleep pose")
	var resting_position := pet.global_position
	await create_timer(0.25).timeout
	check(pet.global_position.distance_to(resting_position)<0.1,"sleeping pet stays grounded and stationary")
	check(pet.collision_layer!=0 and not pet.get_node("FootCollision").disabled,"sleep keeps its physics body active")
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
