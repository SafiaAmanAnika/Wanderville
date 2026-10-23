"""Rendered SocialLobby controls and real social API, using disposable accounts."""
import json
import os
import subprocess
import urllib.request
from pathlib import Path

import pytest
from conftest import (
    API_URL, CLIENT, GODOT, Backend, _register, collect,
    account, _get_with_token, requires_godot,
)

pytestmark = [requires_godot, pytest.mark.preserve_rows, pytest.mark.timeout(600)]


@pytest.fixture(scope="module")
def backend(test_engine):
    class IsolatedBackend(Backend):
        def _env(self):
            env = super()._env()
            env["DATABASE_URL"] = test_engine.url.render_as_string(hide_password=False)
            return env
    service = IsolatedBackend().start()
    try:
        service.ensure_accounts(["lobby_player", "lobby_friend", "lobby_request"])
        for name, code in [("lobby_friend", "boy_a"), ("lobby_request", "girl_a")]:
            request = urllib.request.Request(
                API_URL + "/profile", data=json.dumps({"character_code": code}).encode(),
                headers={"Authorization": "Bearer " + account(name)["token"],
                         "Content-Type": "application/json"}, method="PUT",
            )
            with urllib.request.urlopen(request, timeout=10) as response:
                assert response.status == 200
        yield service
    finally:
        service.stop()


def test_rendered_lobby_interactions(backend, harness_dir):
    player, incoming = account("lobby_player"), account("lobby_request")
    request = urllib.request.Request(
        API_URL + "/social/requests",
        data=json.dumps({"target_id": player["player_id"]}).encode(),
        headers={"Authorization": "Bearer " + incoming["token"],
                 "Content-Type": "application/json"}, method="POST",
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        assert response.status == 200
    env = dict(os.environ)
    env.update({
        "WANDERVILLE_API_URL": API_URL,
        "GODOT_ENET_GAMEPLAY": "0",
        "TEST_LOBBY_ONLINE": "1",
        "TEST_LOBBY_OUTPUT": str(harness_dir),
        "APPDATA": str(harness_dir / "userdata"),
    })
    Path(env["APPDATA"]).mkdir(parents=True, exist_ok=True)
    log = harness_dir / "lobby.log"
    handle = log.open("wb")
    process = subprocess.Popen([
        GODOT, "--path", str(CLIENT), "--rendering-method", "gl_compatibility",
        "--resolution", "1280x809", "--script", "res://tests/lobby_interactions.gd",
    ], cwd=CLIENT, env=env, stdout=handle, stderr=subprocess.STDOUT)
    process._wanderville_log = (handle, log)
    _register(process, "social-lobby")
    code, output = collect(process, timeout=300)
    lines = [line for line in output.decode("utf-8", "replace").splitlines()
             if "INTERACTION_" in line or "SCRIPT ERROR" in line or "Parse Error" in line]
    print("\n" + "\n".join(lines))
    assert code == 0, "\n".join(lines)
    assert b"INTERACTION_RESULT failures=0" in output
    assert b"SCRIPT ERROR" not in output
    for name in ["room", "reception-prompt", "dialogue", "search-results", "friends"]:
        assert (harness_dir / (name + ".png")).stat().st_size > 1000
    # Confirm the UI actions persisted through the actual backend.
    friends = _get_with_token("/social/friends", player["token"])["data"]
    requests = _get_with_token("/social/requests", player["token"])["data"]
    assert any(row["username"] == "lobby_request" for row in friends)
    assert any(row["username"] == "lobby_friend" for row in requests)
