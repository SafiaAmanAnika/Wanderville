import os
import shutil
import subprocess
from pathlib import Path

import pytest

CLIENT = Path(__file__).resolve().parents[3] / "client"


def godot() -> str | None:
    for var in ("GODOT_EXE", "TEST_GODOT_EXE"):
        value = os.environ.get(var)
        if value and Path(value).exists():
            return value
    for name in ("godot", "godot4"):
        if found := shutil.which(name):
            return found
    default = Path("/Applications/Godot.app/Contents/MacOS/Godot")
    return str(default) if default.exists() else None


@pytest.mark.skipif(godot() is None, reason="Godot executable not available")
@pytest.mark.timeout(300)
def test_every_client_script_and_menu_scene_loads():
    """Parse every script under Scripts/ and autoloads/, subfolders included.

    A duplicate declaration in Scripts/inventory/storage_menu.gd once reached
    the running game because nothing ran this check.
    """
    result = subprocess.run(
        [godot(), "--headless", "--path", str(CLIENT),
         "--script", "res://tests/load_check.gd"],
        capture_output=True, text=True, timeout=280,
    )
    output = result.stdout + result.stderr
    failed = [line for line in output.splitlines() if line.startswith("CLIENT_LOAD_FAIL")]
    assert "CLIENT_LOAD_CHECK failures=0" in output and result.returncode == 0, (
        failed or output[-3000:]
    )
