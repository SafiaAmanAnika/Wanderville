"""Two rendered Godot windows, the real movement stack, real server authority.

This is the practical counterpart to the headless movement module. Nothing here
is mocked: two graphical windows run the same admission, the same socket, the
same MovementClient and the same server-authoritative simulation that the
headless tests exercise, and they are observed through RESULT lines and PNGs
rather than through a JSON dump alone.

Two windows need a keyboard nobody is pressing, so each is driven by
TEST_INPUT_SCRIPT. That feeds MovementClient.scripted_input, which is the field
the harness already uses; with the variable unset the same scene reads real WASD,
and the manual checklist at the bottom of this file is for that case.

Every process is registered with conftest's _register, which tracks PIDs, so
teardown kills exactly what this run started and never a Godot process by name.
"""

import json
import os
import re
import subprocess
import threading
import time
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[4]  # repository root, above code/
CLIENT = REPO / "code" / "client"

from conftest import (
    API_URL,
    GODOT,
    account,
    _register,
    collect,
    movement_env,
    reap,
    read_movement_dump,
    start_server,
)

pytestmark = [pytest.mark.integration, pytest.mark.timeout(600)]

SCENE = "res://Scenes/network/RenderedMovement.tscn"
HOST = "127.0.0.1"



def _launch(user: dict, secret: str, port: int, workdir: Path, shots: Path,
            script: str, role: str, run_id: str, seconds: float = 0.0):
    """Launch one real rendered window with its own log file."""
    env = dict(os.environ)
    env.update(movement_env(workdir))
    env.update({
        "TEST_API_URL": API_URL,
        "TEST_TOKEN": user["token"],
        "TEST_USERNAME": user["username"],
        "TEST_HOST": HOST,
        "TEST_PORT": str(port),
        "TEST_SCREENSHOT_DIR": str(shots),
        "TEST_RUN_SECONDS": str(seconds),
    })
    if script:
        env["TEST_INPUT_SCRIPT"] = script
    log = workdir / f"rendered-mv-{role}-{user['username']}-{run_id}.log"
    handle = open(log, "wb")
    # No --headless: opening and rendering a window is the thing under test.
    process = subprocess.Popen(
        [GODOT, "--path", str(CLIENT), SCENE],
        cwd=str(CLIENT), env=env, stdout=handle, stderr=subprocess.STDOUT,
    )
    process._wanderville_log = (handle, log)  # type: ignore[attr-defined]
    _register(process, f"rendered-mv:{role}:{user['username']}")
    return process


def _wait_for_text(process, needle: str, timeout: float, what: str) -> bytes:
    """Wait for a marker in a live window's log, returning the log read so far."""
    deadline = time.time() + timeout
    path = process._wanderville_log[1]  # type: ignore[attr-defined]
    while time.time() < deadline:
        if path.exists():
            text = path.read_bytes()
            if needle.encode() in text:
                return text
        if process.poll() is not None:
            text = path.read_bytes() if path.exists() else b""
            raise AssertionError(
                f"{what}: window exited early with {process.returncode}\n"
                + text.decode("utf-8", "replace")[-1500:]
            )
        time.sleep(0.5)
    text = path.read_bytes() if path.exists() else b""
    raise AssertionError(
        f"{what}: never saw {needle!r} within {timeout}s\n"
        + text.decode("utf-8", "replace")[-1500:]
    )


def _live_log(process) -> bytes:
    """Read a still-running window's log without closing its handle."""
    path = process._wanderville_log[1]  # type: ignore[attr-defined]
    return path.read_bytes() if path.exists() else b""


def _finish_pair(*procs) -> list[bytes]:
    """Let both windows reach their own run limit, then reap and return logs."""
    tails = []
    for proc in procs:
        try:
            proc.wait(timeout=90)
        except subprocess.TimeoutExpired:
            proc.terminate()
        reap(proc)
        path = proc._wanderville_log[1]  # type: ignore[attr-defined]
        tails.append(path.read_bytes() if path.exists() else b"")
    return tails


def _summary(text: bytes) -> dict:
    """The last RESULT summary line, parsed into its key=value fields."""
    for line in reversed(text.decode("utf-8", "replace").splitlines()):
        if not line.startswith("RESULT summary="):
            continue
        parsed = {}
        for bit in line.split(" ")[1:]:
            key, sep, value = bit.partition("=")
            if sep:
                parsed[key] = value
        return parsed
    raise AssertionError(f"no summary line in:\n{text.decode('utf-8', 'replace')[-800:]}")


def _results(text: bytes) -> list[dict]:
    found = []
    for line in text.decode("utf-8", "replace").splitlines():
        if line.startswith("RESULT "):
            payload = {}
            for bit in line[len("RESULT "):].split():
                if "=" in bit:
                    key, _, val = bit.partition("=")
                    payload[key] = val
            found.append(payload)
    return found


def test_two_rendered_windows_see_each_other_move_and_reconnect_once(
    backend, harness_dir, server_port, freed_ports,
):
    backend.ensure_accounts(["rmv_alpha", "rmv_beta"])
    alpha = account("rmv_alpha")
    beta = account("rmv_beta")
    assert alpha["username"] != beta["username"]

    workdir = harness_dir / f"rendered-{server_port}"
    workdir.mkdir(parents=True, exist_ok=True)
    shots = workdir / "shots"
    shots.mkdir(parents=True, exist_ok=True)
    run_id = f"r{server_port}"

    secret = backend.secret
    server = start_server(
        secret=secret,
        port=server_port,
        workdir=workdir,
        extra_env=movement_env(workdir),
    )

    # Alpha walks right, beta walks up: different axes, so "beta saw alpha move"
    # and "alpha saw beta move" cannot be satisfied by one shared value.
    alpha_proc = _launch(alpha, secret, server_port, workdir, shots,
                         "right:2.5", "alpha", run_id, seconds=34.0)
    beta_proc = _launch(beta, secret, server_port, workdir, shots,
                        "up:2.5", "beta", run_id, seconds=34.0)
    # Launched here, not later: the witness has to be present for the players'
    # departure and return, which are what phase 3 measures. It stands still and
    # is never driven, so it cannot perturb what it observes.
    witness_proc = _launch(
        account("rmv_witness"), secret, server_port, workdir, shots,
        "", "witness", run_id, seconds=150.0,
    )

    # Both windows must actually be graphical.
    for label, proc in (("alpha", alpha_proc), ("beta", beta_proc)):
        text = _wait_for_text(proc, "[RenderedMovement] display=", 45, f"{label} start")
        match = re.search(rb"\[RenderedMovement\] display=(\w+)", text)
        assert match, f"{label} never reported a display"
        assert match.group(1).decode() != "headless", (
            f"{label} came up headless; this test needs a real window"
        )

    alpha_text = _wait_for_text(alpha_proc, "RESULT remote_joined", 60, "alpha sees beta")
    beta_text = _wait_for_text(beta_proc, "RESULT remote_joined", 60, "beta sees alpha")

    alpha_res = _results(alpha_text)
    beta_res = _results(beta_text)
    alpha_admitted = [r for r in alpha_res if "admitted" in r]
    beta_admitted = [r for r in beta_res if "admitted" in r]
    assert alpha_admitted, f"alpha never reported admission: {alpha_res}"
    assert beta_admitted, f"beta never reported admission: {beta_res}"

    alpha_pid = int(alpha_admitted[0]["admitted"])
    beta_pid = int(beta_admitted[0]["admitted"])
    assert alpha_pid != beta_pid, "the two windows were admitted as one player"

    # Each window joined the other, and neither joined itself.
    alpha_seen = [int(r["remote_joined"]) for r in alpha_res if "remote_joined" in r]
    beta_seen = [int(r["remote_joined"]) for r in beta_res if "remote_joined" in r]
    assert beta_pid in alpha_seen, f"alpha joined {alpha_seen}, beta is {beta_pid}"
    assert alpha_pid in beta_seen, f"beta joined {beta_seen}, alpha is {alpha_pid}"

    # The server is the authority: both players actually moved, apart from each

# --- phase 2: the server is the authority while both are still connected ---

    # The dump is rewritten on the server's own timer, and once both players have
    # walked and stopped it shows a stationary position. Sampling only after the
    # windows are admitted therefore catches the player at rest, which is
    # indistinguishable from never having moved. So sample from the moment the
    # server is up, on a thread, and keep the per-axis extremes: a player told to
    # walk right sweeps a wide range of x and barely any y, and a player told to
    # walk up does the opposite.
    extremes: dict[int, dict] = {}
    dump_path = workdir / "movement-dump.json"
    watching = threading.Event()
    watching.set()

    def _sample() -> None:
        while watching.is_set():
            try:
                sample = json.loads(dump_path.read_text(encoding="utf-8"))
            except Exception:
                sample = {}
            for ent in sample.get("entities") or []:
                pid = ent.get("player_id")
                x, y = ent.get("x"), ent.get("y")
                if pid is None or x is None or y is None:
                    continue
                slot = extremes.setdefault(pid, {"minx": x, "maxx": x, "miny": y, "maxy": y})
                slot["minx"] = min(slot["minx"], x)
                slot["maxx"] = max(slot["maxx"], x)
                slot["miny"] = min(slot["miny"], y)
                slot["maxy"] = max(slot["maxy"], y)
            time.sleep(0.25)

    sampler = threading.Thread(target=_sample, daemon=True)
    sampler.start()

    # Both windows must actually be graphical.
    for label, proc in (("alpha", alpha_proc), ("beta", beta_proc)):
        text = _wait_for_text(proc, "[RenderedMovement] display=", 45, f"{label} start")
        match = re.search(rb"\[RenderedMovement\] display=(\w+)", text)
        assert match, f"{label} never reported a display"
        assert match.group(1).decode() != "headless", (
            f"{label} came up headless; this test needs a real window"
        )

    alpha_text = _wait_for_text(alpha_proc, "RESULT remote_joined", 60, "alpha sees beta")
    beta_text = _wait_for_text(beta_proc, "RESULT remote_joined", 60, "beta sees alpha")

    alpha_res = _results(alpha_text)
    beta_res = _results(beta_text)
    alpha_admitted = [r for r in alpha_res if "admitted" in r]
    beta_admitted = [r for r in beta_res if "admitted" in r]
    assert alpha_admitted, f"alpha never reported admission: {alpha_res}"
    assert beta_admitted, f"beta never reported admission: {beta_res}"

    alpha_pid = int(alpha_admitted[0]["admitted"])
    beta_pid = int(beta_admitted[0]["admitted"])
    assert alpha_pid != beta_pid, "the two windows were admitted as one player"

    # Each window joined the other, and neither joined itself.
    alpha_seen = [int(r["remote_joined"]) for r in alpha_res if "remote_joined" in r]
    beta_seen = [int(r["remote_joined"]) for r in beta_res if "remote_joined" in r]
    assert beta_pid in alpha_seen, f"alpha joined {alpha_seen}, beta is {beta_pid}"
    assert alpha_pid in beta_seen, f"beta joined {beta_seen}, alpha is {alpha_pid}"

    # Wait for the scripted walk to have actually happened.
    deadline = time.time() + 40
    while time.time() < deadline:
        a, b = extremes.get(alpha_pid), extremes.get(beta_pid)
        if a and b and (a["maxx"] - a["minx"] > 50) and (b["maxy"] - b["miny"] > 50):
            break
        time.sleep(0.5)

    watching.clear()
    sampler.join(timeout=5)

    a, b = extremes.get(alpha_pid), extremes.get(beta_pid)
    assert a, f"alpha {alpha_pid} never appeared in the server dump"
    assert b, f"beta {beta_pid} never appeared in the server dump"

    # Alpha was told to walk right, beta to walk up. The server's own coordinates
    # must show horizontal travel for one and vertical for the other; that is only
    # possible if the server integrated each player's own input.
    a_dx = a["maxx"] - a["minx"]
    b_dy = b["maxy"] - b["miny"]
    assert a_dx > 50, f"alpha was told to walk right but only swept x by {a_dx}"
    assert b_dy > 50, f"beta was told to walk up but only swept y by {b_dy}"
    assert b["maxx"] - b["minx"] < a_dx / 2, "beta was carried sideways by alpha's input"

    # The client never sets its own position from anything but a snapshot, so a
    # growing correction count would mean the two disagreed about where the player
    # is. A little is normal while reconciling; a lot is not.
    alpha_tail, beta_tail = _finish_pair(alpha_proc, beta_proc)
    alpha_sum = _summary(alpha_tail)
    beta_sum = _summary(beta_tail)
    assert not alpha_sum.get("errors"), f"alpha reported errors: {alpha_sum}"
    assert not beta_sum.get("errors"), f"beta reported errors: {beta_sum}"
    assert int(alpha_sum["remotes"]) >= 1, alpha_sum
    assert int(beta_sum["remotes"]) >= 1, beta_sum
    assert int(alpha_sum["snapshots"]) > 0, alpha_sum
    assert int(beta_sum["snapshots"]) > 0, beta_sum

    pngs = sorted(shots.glob("*.png"))
    assert pngs, f"no screenshots were written to {shots}"
    assert any(p.stat().st_size > 1000 for p in pngs), "screenshots are suspiciously empty"

    print(f"\nscreenshots: {[p.name for p in pngs]}")
    print(f"alpha: {alpha_sum}")
    print(f"beta:  {beta_sum}")

    # --- phase 3: disconnect removes the right avatar, reconnect makes one ---

    # The witness must already be in the world while alpha and beta are, because
    # it is their leaving and returning that it has to report. Launching it after
    # they are gone would leave it with nothing to observe, and "exactly one
    # avatar" would be unfalsifiable: with nobody else present, zero remotes and
    # one remote look the same from inside the window.
    witness_text = _wait_for_text(witness_proc, "RESULT remote_joined", 60, "witness joins")
    witness_res = _results(witness_text)
    witness_pid = int([r for r in witness_res if "admitted" in r][0]["admitted"])
    assert witness_pid not in (alpha_pid, beta_pid), "the witness is one of the players"
    assert {alpha_pid, beta_pid} <= {
        int(r["remote_joined"]) for r in witness_res if "remote_joined" in r
    }, "the witness did not see both players"

    # Alpha and beta now reach their own run limit and leave.
    _finish_pair(alpha_proc, beta_proc)

    def _witness_events(key: str) -> list[int]:
        return [int(r[key]) for r in _results(_live_log(witness_proc)) if key in r]

    deadline = time.time() + 45
    left: list[int] = []
    while time.time() < deadline:
        left = _witness_events("remote_left")
        if {alpha_pid, beta_pid} <= set(left):
            break
        time.sleep(1.0)

    assert set(left) >= {alpha_pid, beta_pid}, (
        f"the witness lost {sorted(set(left))}; both players should have left"
    )

# Beta comes back on a fresh ticket, same account, same player id.
    # Counted from the departure, not from the start of the session: beta also
    # joined once before it left, and counting that would make a correct reconnect
    # look like a duplicate.
    joins_at_departure = len([i for i in _witness_events("remote_joined") if i == beta_pid])
    assert joins_at_departure == 1, (
        f"beta should have joined exactly once before leaving, saw {joins_at_departure}"
    )

    beta2 = _launch(beta, secret, server_port, workdir, shots,
                    "", "beta2", f"{run_id}b", seconds=40.0)
    _wait_for_text(beta2, "RESULT admitted", 60, "beta rejoins")

    # Exactly one avatar: beta is seen joining again, once more, under the same id
    # it left with. A reconnect that minted a second avatar would show up here as
    # a third sighting or as a different id.
    deadline = time.time() + 45
    total: list[int] = []
    while time.time() < deadline:
        total = [i for i in _witness_events("remote_joined") if i == beta_pid]
        if len(total) > joins_at_departure:
            break
        time.sleep(1.0)

    assert len(total) == joins_at_departure + 1, (
        f"the witness saw beta join {len(total)} times after departing once; "
        "a reconnect must produce exactly one avatar"
    )
    assert set(total) == {beta_pid}, f"beta reappeared under unexpected ids: {total}"

    reap(witness_proc)
    reap(beta2)

    print(f"\nwitness: joined={sorted({int(r['remote_joined']) for r in witness_res if 'remote_joined' in r})}"
          f" left={sorted(set(left))} joins_for_beta={len(total)}")
    print(f"screenshots: {len(pngs)} in {shots}")