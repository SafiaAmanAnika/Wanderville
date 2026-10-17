"""External watchdog for the real-process Godot integration tests.

Run this alongside pytest when a suite may exceed its deadline:

    python tests/integration/watchdog.py --pid <pytest-pid> --timeout 900

pytest-timeout's thread method can terminate pytest without running fixture
teardown, so the autouse cleanup in ``conftest.py`` may never fire and Godot
child processes can survive. This closes that gap: it waits for the pytest
process to exit and, if pytest is still alive past the deadline, kills the
process **tree** of that PID only.

Safety: it kills the tree of the PID it is given, and nothing else. It does not
match on process name, so a Godot editor, a database, or any other unrelated
process is never a target. Every PID it kills is a descendant of the pytest
process this supervisor was pointed at.

The PID registry file that ``conftest.py`` writes is read only to report what was
leaked; cleanup itself is driven by process parentage.
"""

import argparse
import os
import sys
import time


def _children_recursive(pid):
    import psutil

    try:
        return psutil.Process(pid).children(recursive=True)
    except psutil.Error:
        return []


def _kill_tree(pid):
    """Kill descendants first, then the parent, then insist."""
    import psutil

    victims = _children_recursive(pid)
    try:
        parent = psutil.Process(pid)
        victims.append(parent)
    except psutil.Error:
        parent = None
    for victim in victims:
        try:
            victim.kill()
        except psutil.Error:
            pass
    gone, alive = psutil.wait_procs(victims, timeout=10)
    for survivor in alive:
        try:
            survivor.kill()
        except psutil.Error:
            pass
    return len(gone), len(alive)


def _read_registered():
    path = os.environ.get(
        "WANDERVILLE_TEST_PIDFILE",
        os.path.join(os.environ.get("TEMP", "."), "wanderville_test_pids.txt"),
    )
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return [int(part) for part in handle.read().split() if part.strip()]
    except (OSError, ValueError):
        return []


def _alive(pid):
    import psutil

    try:
        return psutil.pid_exists(pid)
    except Exception:  # noqa: BLE001 - liveness probe only
        return False


def _sweep_registered():
    """Kill anything still alive that conftest registered as ours.

    Needed because pytest-timeout's thread method terminates pytest *without*
    running fixture teardown. When pytest dies its Godot grandchildren are
    reparented and the autouse cleanup never runs, so they survive and hold UDP
    ports. The registry file is the authoritative list of processes this harness
    created, and each is verified to still look like what it was before it is
    killed.
    """
    import psutil

    killed = []
    for pid in _read_registered():
        if not _alive(pid):
            continue
        try:
            proc = psutil.Process(pid)
            name = proc.name().lower()
            cmdline = " ".join(proc.cmdline()).lower()
        except psutil.Error:
            continue
        # Only ever kill something this harness started. The registry is the first
        # gate; the image-name check is the second, so a recycled PID belonging to
        # something else is left alone.
        if not ("godot" in name or "python" in name or "uvicorn" in name):
            continue
        if not ("wanderville" in cmdline or "godot" in cmdline or "uvicorn" in cmdline):
            continue
        _kill_tree(pid)
        killed.append(pid)
    return killed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pid", type=int, required=True, help="pytest process id")
    parser.add_argument(
        "--timeout", type=float, default=900.0,
        help="seconds to allow pytest before killing its tree",
    )
    parser.add_argument(
        "--poll", type=float, default=2.0, help="seconds between checks"
    )
    args = parser.parse_args()

    deadline = time.monotonic() + args.timeout
    last_report = 0.0
    while time.monotonic() < deadline:
        if not _alive(args.pid):
            print(f"[watchdog] pytest {args.pid} exited", flush=True)
            # pytest may have been killed without teardown; sweep regardless.
            leaked = _sweep_registered()
            if leaked:
                print(f"[watchdog] swept {len(leaked)} orphaned pid(s): {leaked}", flush=True)
                return 2
            print("[watchdog] no leaked processes", flush=True)
            return 0
        now = time.monotonic()
        if now - last_report >= 30.0:
            registered = _read_registered()
            print(
                f"[watchdog] {int(deadline - now)}s remaining; "
                f"{len(registered)} registered child pid(s)",
                flush=True,
            )
            last_report = now
        time.sleep(args.poll)

    print(
        f"[watchdog] deadline exceeded; killing the tree of pytest pid {args.pid}",
        flush=True,
    )
    gone, alive = _kill_tree(args.pid)
    print(f"[watchdog] terminated {gone} process(es), {alive} stubborn", flush=True)
    leaked = _sweep_registered()
    if leaked:
        print(f"[watchdog] WARNING still alive after kill: {leaked}", flush=True)
        return 2
    print("[watchdog] no leaked processes", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())