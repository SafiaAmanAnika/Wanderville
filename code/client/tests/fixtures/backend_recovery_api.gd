extends "res://autoloads/APIClient.gd"

var fail_path := ""
var calls: Array[String] = []


func authenticated(_method: int, path: String, _body: Variant = null) -> Dictionary:
	calls.append(path)
	await get_tree().process_frame
	if path == fail_path:
		return {"ok": false, "message": "Temporary connection failure"}
	var payloads := {
		"/profile": {"character_code": "girl_a", "map_code": "campus", "water_charges": 7},
		"/world/me": {"id": 10},
		"/economy/": {"aura_balance": 15},
		"/inventory/": {"items": []},
		"/world/state": {"current_season": "summer"},
		"/farm/plots": {"world_id": 10, "plots": []},
		"/economy/xp": {"level": 1},
		"/farm/visiting/session": {"owned_world_id": 10, "current_world_id": 10, "session_mode": "OWNER"},
	}
	return {"ok": true, "body": {"data": payloads.get(path, {})}}
