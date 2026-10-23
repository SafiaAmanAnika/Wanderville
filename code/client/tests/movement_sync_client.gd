extends "res://autoloads/RealtimeClient.gd"
var sent: Array = []
func _send(kind: String, payload: Dictionary) -> bool:
	sent.append({"kind": kind, "payload": payload})
	return true
