"""Normal world clients: real HTTP login, WebSocket services, ENet movement."""
import json
import os
import re
import subprocess
from pathlib import Path

import pytest
from conftest import (
    API_URL, CLIENT, GODOT, Backend, _register, collect,
    movement_env, requires_godot, start_server,
)

pytestmark = [requires_godot, pytest.mark.preserve_rows, pytest.mark.timeout(600)]


@pytest.fixture(scope="module")
def backend(test_engine):
    # The parent fixture creates a disposable DB; never inherit DATABASE_URL.
    class IsolatedBackend(Backend):
        def _env(self):
            env = super()._env()
            env["DATABASE_URL"] = test_engine.url.render_as_string(hide_password=False)
            return env
    service = IsolatedBackend().start()
    service.ensure_accounts(["gameplay_alpha", "gameplay_beta"])
    yield service
    service.stop()


def launch(role, port, directory, *, legacy=False, mismatch=False, rendered=False):
    directory.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    env.update({
        "WANDERVILLE_API_URL": API_URL,
        "GODOT_MULTIPLAYER_HOST": "127.0.0.1",
        "GODOT_MULTIPLAYER_PORT": str(port),
        "GODOT_ENET_GAMEPLAY": "0" if legacy else "1",
        "TEST_ROLE": role, "TEST_SYNC_DIR": str(directory),
        "TEST_LEGACY": "1" if legacy else "0",
        "TEST_BAD_VERSION": "1" if mismatch else "0",
        # Isolate Godot saves/logs from the user's account and the other client.
        "APPDATA": str(directory / (role + "-userdata")),
    })
    env.pop("GODOT_MOVEMENT_ARENA", None)
    env.pop("GODOT_COLLISION_CACHE", None)
    env.pop("TEST_TICKET_OVERRIDE", None)
    if not os.environ.get("WANDERVILLE_GAMEPLAY_MANUAL_SECONDS"):
        env.pop("TEST_MANUAL_SECONDS", None)
    else:
        env["TEST_MANUAL_SECONDS"] = os.environ["WANDERVILLE_GAMEPLAY_MANUAL_SECONDS"]
    Path(env["APPDATA"]).mkdir(parents=True, exist_ok=True)
    log = directory / (role + ".log")
    handle = log.open("wb")
    args = [GODOT, "--path", str(CLIENT), "--rendering-method", "gl_compatibility",
            "--resolution", "1100x720", "--position", "0,60" if role == "alpha" else "800,60",
            "--script", "res://tests/enet_gameplay.gd"]
    if not rendered:
        args.append("--headless")
    process = subprocess.Popen(args, cwd=CLIENT, env=env, stdout=handle, stderr=subprocess.STDOUT)
    process._wanderville_log = (handle, log)
    return _register(process, "normal-world:" + role)


def result(process, timeout=180):
    timeout = max(timeout, int(os.environ.get("WANDERVILLE_GAMEPLAY_MANUAL_SECONDS", "0")) + 180)
    code, output = collect(process, timeout)
    lines = [line for line in output.decode("utf-8", "replace").splitlines()
             if "GAMEPLAY_" in line or "SCRIPT ERROR" in line or "Parse Error" in line]
    print("\n" + "\n".join(lines))
    assert code == 0, "\n".join(lines[-30:])
    matches = re.findall(rb"GAMEPLAY_RESULT (\{[^\r\n]+\})", output)
    assert matches, "normal-world driver did not finish"
    record = json.loads(matches[-1])
    assert record["failures"] == 0, lines
    assert record["scene"] == "res://Scenes/world.tscn"
    assert b"SCRIPT ERROR" not in output
    return record


def test_two_normal_world_clients(backend, harness_dir, server_port):
    server = start_server(backend.secret, server_port, harness_dir,
                          {**movement_env(harness_dir, arena=False), "GODOT_ENET_GAMEPLAY": "1"})
    a = launch("alpha", server_port, harness_dir, rendered=True)
    b = launch("beta", server_port, harness_dir, rendered=True)
    one, two = result(a), result(b)
    assert one["player_id"] != two["player_id"]
    assert one["display"] != "headless" and two["display"] != "headless"
    if not os.environ.get("WANDERVILLE_GAMEPLAY_MANUAL_SECONDS"):
        assert (harness_dir / "alpha.png").stat().st_size > 1000
        assert (harness_dir / "beta.png").stat().st_size > 1000
    assert server.poll() is None


def test_incompatible_campus_is_rejected(backend, harness_dir, server_port):
    start_server(backend.secret, server_port, harness_dir,
                 {**movement_env(harness_dir, arena=False), "GODOT_ENET_GAMEPLAY": "1"})
    result(launch("alpha", server_port, harness_dir, mismatch=True))


def test_normal_world_defaults_to_legacy(backend, harness_dir, server_port):
    result(launch("alpha", server_port, harness_dir, legacy=True))
