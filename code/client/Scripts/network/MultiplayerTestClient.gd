extends Node
class_name MultiplayerTestClient
## A headless client used only by the integration harness.
##
## It performs the full real path -- request a ticket from FastAPI, open a real
## UDP connection, present the ticket, and report the verdict -- and prints a
## single machine-readable line so a supervising process can assert on it.
##
## It deliberately loads no world, no character, no HUD and no camera. There is
## nothing here that could be mistaken for a movement authority.

signal finished(result: Dictionary)

const LABEL := "[TestClient]"

var client: MultiplayerClient
var player_id := 0
var username := ""
var host := NetworkConfig.DEFAULT_HOST
var port := NetworkConfig.DEFAULT_PORT

var _result := {}


func setup(api_base_url: String, token: String, user_id: int, name_hint: String) -> void:
	username = name_hint
	client = MultiplayerClient.new()
	add_child(client)
	client.configure(api_base_url, token)
	client.admitted.connect(_on_admitted)
	client.rejected.connect(_on_rejected)
	player_id = user_id


func run(server_host: String, server_port: int) -> void:
	host = server_host
	port = server_port
	print("%s starting: host=%s port=%d username=%s" % [LABEL, host, port, username])
	client.connect_to_server(host, port)


func _on_admitted(result: Dictionary) -> void:
	_result = {
		"ok": true,
		"event": "admitted",
		"username": username,
		# Both come from the backend via the server's admit_result, never from
		# the local account fixture.
		"player_id": int(result.get("player_id", 0)),
		"room": str(result.get("room", "")),
		"server_id": str(result.get("server_id", "")),
		"server_username": str(result.get("username", "")),
	}
	_emit()
	# Stay connected so a supervisor can observe a live peer before we exit.
	var hold := float(OS.get_environment("TEST_CLIENT_HOLD_SECONDS"))
	if hold <= 0.0:
		hold = 2.0
	await get_tree().create_timer(hold).timeout
	_finish()


func _on_rejected(reason: String) -> void:
	_result = {
		"ok": false,
		"event": "rejected",
		"username": username,
		"reason": reason,
	}
	_emit()
	_finish()


func _emit() -> void:
	print("RESULT " + JSON.stringify(_result))
	finished.emit(_result)


func _finish() -> void:
	client.disconnect_from_server()
	finished.emit(_result)
	get_tree().quit(0 if bool(_result.get("ok", false)) else 1)