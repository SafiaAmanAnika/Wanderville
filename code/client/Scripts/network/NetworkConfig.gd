extends RefCounted
class_name NetworkConfig
## Central configuration for the Godot multiplayer transport.
##
## Every value can be overridden from the environment so the same build works
## on a developer machine and on a test host, and so nothing here has to change
## to point a second client at a different server.
##
## Nothing in this class is a secret. The internal host secret lives in the
## Python backend's environment and must never be copied into the client.

## Which transport carries live movement. "legacy" is the existing Python
## WebSocket path and remains the default; the Godot ENet path is opt-in and
## does not move characters yet.
const DEFAULT_TRANSPORT := "legacy"

## Where the dedicated multiplayer server listens.
const DEFAULT_HOST := "127.0.0.1"
const DEFAULT_PORT := 24567

## How long a peer has to present a valid admission ticket before it is dropped.
const DEFAULT_AUTH_TIMEOUT_SECONDS := 10.0

## How often the client retries a failed connection, and the backoff ceiling.
const DEFAULT_RETRY_DELAY_SECONDS := 1.0
const DEFAULT_MAX_RETRY_DELAY_SECONDS := 15.0
const DEFAULT_MAX_RETRIES := 5


static func transport() -> String:
	return _env("WANDERVILLE_MULTIPLAYER_TRANSPORT", DEFAULT_TRANSPORT)


static func uses_godot_multiplayer() -> bool:
	return transport() == "godot-enet"


static func host() -> String:
	return _env("GODOT_MULTIPLAYER_HOST", DEFAULT_HOST)


static func port() -> int:
	return int(_env("GODOT_MULTIPLAYER_PORT", str(DEFAULT_PORT)))


static func auth_timeout() -> float:
	return float(_env("GODOT_MULTIPLAYER_AUTH_TIMEOUT", str(DEFAULT_AUTH_TIMEOUT_SECONDS)))


static func max_retries() -> int:
	return int(_env("GODOT_MULTIPLAYER_MAX_RETRIES", str(DEFAULT_MAX_RETRIES)))


## Read an environment variable, tolerating a missing environment entirely.
##
## The dedicated server is launched with --headless, where OS.get_environment
## still works, but a scripted test harness may not have one at all.
static func _env(key: String, fallback: String) -> String:
	var value := OS.get_environment(key)
	if value == "":
		var project_value := str(
			ProjectSettings.get_setting("network/" + key.to_lower(), "")
		)
		if project_value != "":
			return project_value
		return fallback
	return value