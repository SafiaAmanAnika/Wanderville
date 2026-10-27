"""Real account -> world -> pet selector -> HTTP save -> world reload."""
import json
import os
import subprocess
from pathlib import Path

import pytest
from conftest import API_URL, CLIENT, GODOT, Backend, _register, collect, account, requires_godot

pytestmark = [requires_godot, pytest.mark.preserve_rows, pytest.mark.timeout(180)]


@pytest.fixture
def backend(test_engine):
    class IsolatedBackend(Backend):
        def _env(self):
            env = super()._env()
            env["DATABASE_URL"] = test_engine.url.render_as_string(hide_password=False)
            return env
    service = IsolatedBackend().start()
    try:
        service.ensure_accounts(["pet_companion_player"])
        yield service
    finally:
        service.stop()


def test_pet_selection_survives_world_reload(backend, harness_dir):
    env = {**os.environ, "WANDERVILLE_API_URL": API_URL, "GODOT_ENET_GAMEPLAY": "0",
           "TEST_PET_ACCOUNT": json.dumps(account("pet_companion_player")),
           "APPDATA": str(harness_dir / "userdata")}
    Path(env["APPDATA"]).mkdir(parents=True, exist_ok=True)
    log = harness_dir / "pets.log"
    with log.open("wb") as handle:
        process = subprocess.Popen(
            [GODOT, "--headless", "--path", str(CLIENT), "--script", "res://tests/pet_authenticated_check.gd"],
            cwd=CLIENT, env=env, stdout=handle, stderr=subprocess.STDOUT)
        process._wanderville_log = (handle, log)
        _register(process, "pet-companions")
        code, output = collect(process, timeout=90)
    lines = output.decode("utf-8", "replace").splitlines()
    print("\n".join(line for line in lines if "PET_AUTH" in line or "SCRIPT ERROR" in line))
    assert code == 0 and b"PET_AUTH_RESULT failures=0" in output
    assert b"SCRIPT ERROR" not in output
