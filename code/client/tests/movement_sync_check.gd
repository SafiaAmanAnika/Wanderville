extends SceneTree

var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	print("SYNC_CHECK ", label, " ", "PASS" if ok else "FAIL")
	if not ok: failures += 1
func snapshot(client: Node, position: Vector2, sequence: int) -> void:
	client._handle_packet({"type":"snapshot", "data":{"room":"campus", "players":[
		{"player_id":918274, "x":position.x, "y":position.y, "sequence":sequence}
	]}})
func run() -> void:
	var session := root.get_node("Global")
	session.player_id = 918274
	session.token = "isolated-sync-test"
	var body := Node2D.new()
	body.add_to_group("player")
	root.add_child(body)
	var layout := preload("res://Scripts/network/CampusLayout.gd")
	var origin := layout.spawn()
	body.position = origin
	var client = load("res://tests/movement_sync_client.gd").new()
	root.add_child(client)
	client.set_process(false)
	snapshot(client, origin, 0)
	body.position.x += 30
	client._send_movement(0.21)
	body.position.x += 30
	client._send_movement(0.21)
	check(client.sent.size() == 2, "second_movement_does_not_wait_for_first_round_trip")
	body.position.x += 30
	client._send_movement(0.21)
	check(client.sent.size() == 2, "slow_connection_queue_is_bounded")
	snapshot(client, origin+Vector2(30,0), 1)
	client._send_movement(0.21)
	check(client.sent.size() == 3, "acknowledgment_releases_one_slot")
	client._correct_position = true
	body.position = origin+Vector2(100,0)
	snapshot(client, origin, 3)
	check(body.position == origin+Vector2(100,0), "reconnect_keeps_small_local_lead")
	var count: int = client.sent.size()
	client._send_movement(0.21)
	check(client.sent.size() == count+1, "reconnect_publishes_retained_local_position")
	client._handle_packet({"type":"error", "error":"COLLISION", "status":400, "message":"blocked"})
	snapshot(client, origin, 3)
	check(body.position == origin, "rejected_move_restores_authority_even_below_400_units")
	body.position = origin+Vector2(600,0)
	client.pause_movement = true
	client._correct_position = true
	snapshot(client, origin, 3)
	check(body.position == origin+Vector2(600,0), "house_pause_does_not_teleport_player")
	session.token = ""
	session.player_id = 0
	print("SYNC_RESULT failures=", failures)
	quit(failures)
