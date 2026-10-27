"""Rendered farm clicks through normal routing and real authenticated HTTP."""
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
        service.ensure_accounts(["farm_input_player"])
        yield service
    finally:
        service.stop()


def test_rendered_authenticated_farm_click(backend, harness_dir):
    env = {**os.environ, "WANDERVILLE_API_URL": API_URL, "GODOT_ENET_GAMEPLAY": "0",
           "TEST_FARM_ACCOUNT": json.dumps(account("farm_input_player")),
           "TEST_FARM_OUTPUT": str(harness_dir), "APPDATA": str(harness_dir / "userdata")}
    Path(env["APPDATA"]).mkdir(parents=True, exist_ok=True)
    log = harness_dir / "farming.log"
    with log.open("wb") as handle:
        process = subprocess.Popen(
            [GODOT, "--path", str(CLIENT), "--rendering-method", "gl_compatibility",
             "--position", "20000,20000", "--script", "res://tests/farming_authenticated_check.gd"],
            cwd=CLIENT, env=env, stdout=handle, stderr=subprocess.STDOUT)
        process._wanderville_log = (handle, log)
        _register(process, "farming-input")
        code, output = collect(process, timeout=90)
    lines = output.decode("utf-8", "replace").splitlines()
    print("\n".join(line for line in lines if "FARM_AUTH" in line or "SCRIPT ERROR" in line))
    assert code == 0 and b"FARM_AUTH_RESULT failures=0" in output
    assert b"SCRIPT ERROR" not in output
