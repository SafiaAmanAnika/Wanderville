"""Rendered two-window verification for the Godot multiplayer stack.

Opens two *real* Godot windows (no ``--headless``), authenticates both against an
isolated FastAPI, and checks that each window reports a live authenticated
session, that both are connected at the same time, that disconnecting one leaves
the other connected, and that the first returns on a new ticket. Screenshots are
written per milestone to ``test-output/rendered``.

This is the check a headless run cannot make: that a window actually opens,
renders, and displays its own authenticated status.

Opt in, because it takes over the desktop:

    RUN_RENDERED_TESTS=1 pytest tests/integration/test_rendered_clients.py -q

Skipped rather than failed when the Godot executable, a display, or the local
PostgreSQL instance is unavailable.
"""

import os
import re
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

import pytest

from conftest import (
    API_URL,
    CLIENT,
    EVIDENCE,
    GODOT,
    HOST,
    RENDERED_SCENE,
    account,
    free_port_is_free,
    parse_results,
    reap,
    _register,
    requires_godot,
    start_server,
    tail,
)

RENDERED = EVIDENCE / "rendered"

pytestmark = [
    requires_godot,
    pytest.mark.preserve_rows,
    pytest.mark.skipif(
        os.environ.get("RUN_RENDERED_TESTS") != "1",
        reason="set RUN_RENDERED_TESTS=1 to open real windows on the desktop",
    ),
]


def _launch(user: dict, secret: str, port: int, workdir: Path, shots: Path):
    """Launch a real rendered window whose output goes to its own file."""
    env = dict(os.environ)
    env.update({
        "MULTIPLAYER_BRIDGE_SECRET": secret,
        "TEST_API_URL": API_URL,
        "TEST_TOKEN": user["token"],
        "TEST_USERNAME": user["username"],
        "TEST_HOST": HOST,
        "TEST_PORT": str(port),
        "TEST_SCREENSHOT_DIR": str(shots),
        "TEST_SCENARIO": "presence",
        "TEST_EXPECT_ROSTER": "2",
    })
    log = workdir / f"rendered-{user['username']}.log"
    handle = open(log, "wb")
    # No --headless: opening and rendering a window is what is under test.
    process = subprocess.Popen(
        [GODOT, "--path", str(CLIENT), RENDERED_SCENE],
        cwd=str(CLIENT), env=env, stdout=handle, stderr=subprocess.STDOUT,
    )
    process._wanderville_log = (handle, log)  # type: ignore[attr-defined]
    _register(process, f"rendered:{user['username']}")
    return process


def test_two_rendered_windows_stay_authenticated_through_reconnect(backend):
    """Two real windows authenticate, coexist, survive one leaving, and return."""
    workdir = Path(tempfile.mkdtemp(prefix="wanderville-rendered-"))
    shots = RENDERED
    shots.mkdir(parents=True, exist_ok=True)
    for stale in shots.glob("*.png"):
        stale.unlink()

    one = account("rnd_alpha")
    two = account("rnd_beta")
    assert one["player_id"] != two["player_id"]

    port = next(p for p in range(24600, 24700) if free_port_is_free(p))

    server = None
    alpha = None
    beta = None
    try:
        server = start_server(
            backend.secret, port, workdir,
            extra_env={"GODOT_MULTIPLAYER_SERVER_ID": "rendered-harness"},
        )
        alpha = _launch(one, backend.secret, port, workdir, shots)
        beta = _launch(two, backend.secret, port, workdir, shots)

        # Both scenarios must finish on their own. Collecting them one after the
        # other would terminate the first before the second finished, and the
        # second would then report a roster of one -- which would look exactly
        # like a reconnect failure.
        deadline = time.time() + 240
        while (alpha.poll() is None or beta.poll() is None) and time.time() < deadline:
            time.sleep(1)

        beta_out = reap(beta, timeout=60).decode("utf-8", "replace")
        alpha_out = reap(alpha, timeout=60).decode("utf-8", "replace")

        # Each window must have reported a real display, not a headless one.
        for name, text in (("alpha", alpha_out), ("beta", beta_out)):
            match = re.search(r"\[RenderedClient\] display=(\w+)", text)
            assert match, (
                f"{name} never reported a display server:\n"
                + tail(text.encode("utf-8"), 1500)
            )
            assert match.group(1) != "headless", (
                f"{name} reported a headless display; this test must render a window"
            )

        results_a = parse_results(alpha_out.encode("utf-8"))
        results_b = parse_results(beta_out.encode("utf-8"))
        assert results_a, alpha_out[-1500:]
        assert results_b, beta_out[-1500:]

        events_a = [r["event"] for r in results_a]
        events_b = [r["event"] for r in results_b]

        assert "admitted" in events_a, events_a
        assert "admitted" in events_b, events_b
        # Both windows saw a roster of two, i.e. they were connected to each other
        # simultaneously rather than one after the other.
        assert "roster_full" in events_a, events_a
        assert "roster_full" in events_b, events_b
        # Each one disconnected and came back on a fresh ticket.
        assert "scenario_complete" in events_a, events_a
        assert "scenario_complete" in events_b, events_b

        admitted_a = next(r for r in results_a if r["event"] == "admitted")
        admitted_b = next(r for r in results_b if r["event"] == "admitted")
        assert admitted_a["player_id"] == one["player_id"], admitted_a
        assert admitted_b["player_id"] == two["player_id"], admitted_b

        # After the round trip each window sees exactly one *other* player, so the
        # reconnect produced no duplicate and no self-copy.
        for name, results, other in (
            ("alpha", results_a, two), ("beta", results_b, one)
        ):
            final = results[-1]
            assert final["event"] == "scenario_complete", (name, results)
            assert final["roster_size"] == 2, (name, final)
            assert final["others"] == [other["player_id"]], (name, final)
            assert final.get("errors") == [], (name, final)

        server_text = reap(server).decode("utf-8", "replace")
        assert server_text.count("admitted peer") >= 3, server_text[-1500:]

        pngs = sorted(shots.glob("*.png"))
        assert pngs, f"no screenshots were written to {shots}"
        assert all(p.stat().st_size > 2000 for p in pngs), [p.name for p in pngs]
        print(f"\nscreenshots: {[p.name for p in pngs]}")
    finally:
        for process in (alpha, beta, server):
            if process is not None:
                reap(process)
        shutil.rmtree(workdir, ignore_errors=True)