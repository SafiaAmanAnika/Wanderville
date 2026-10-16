extends Node
## Headless harness: drives one MultiplayerTestClient from environment variables.
##
##   TEST_API_URL    backend base url           (default http://127.0.0.1:8000)
##   TEST_TOKEN      the player's access token
##   TEST_USERNAME   label for the result line
##   TEST_PLAYER_ID  the authenticated player id, for cross-checking
##   TEST_HOST       multiplayer host           (default 127.0.0.1)
##   TEST_PORT       multiplayer udp port       (default 24567)
##
## Prints exactly one ``RESULT {...}`` line, which the Python supervisor parses.

var client: MultiplayerTestClient


func _ready() -> void:
	client = MultiplayerTestClient.new()
	add_child(client)
	client.setup(
		OS.get_environment("TEST_API_URL"),
		OS.get_environment("TEST_TOKEN"),
		int(OS.get_environment("TEST_PLAYER_ID")),
		OS.get_environment("TEST_USERNAME"),
	)
	client.run(
		OS.get_environment("TEST_HOST"),
		int(OS.get_environment("TEST_PORT")),
	)