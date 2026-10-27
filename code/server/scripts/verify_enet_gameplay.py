"""Run normal-world ENet checks against a new disposable PostgreSQL cluster.
Windows: .venv312/Scripts/python.exe scripts/verify_enet_gameplay.py
Use --manual 300 to open two normal game windows for five minutes.
"""
import argparse
import os
from pathlib import Path
import secrets
import shutil
import socket
import subprocess
import sys

SERVER = Path(__file__).resolve().parents[1]
ROOT = SERVER.parents[1]


def free_port(kind=socket.SOCK_STREAM):
    with socket.socket(type=kind) as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def cleanup_owned(run):
    # Also runs if pytest-timeout exits before fixture teardown. Match the unique
    # inherited marker as well as the recorded PID; never kill by process name.
    import psutil
    pidfile = run / "owned-pids.txt"
    recorded = set(pidfile.read_text().split()) if pidfile.exists() else set()
    # A Windows launcher may exit before its interpreter child; fixture teardown
    # can then remove its PID from the registry. The inherited marker still
    # identifies those children without touching any unrelated local process.
    for candidate in psutil.process_iter():
        try:
            if candidate.environ().get("WANDERVILLE_TEST_PIDFILE") == str(pidfile):
                recorded.add(str(candidate.pid))
        except psutil.Error:
            pass
    for raw in recorded:
        try:
            process = psutil.Process(int(raw))
            marker = process.environ().get("WANDERVILLE_TEST_PIDFILE", "")
            if marker != str(pidfile):
                continue
            children = process.children(recursive=True)
            for child in children:
                child.terminate()
            process.terminate()
            _, alive = psutil.wait_procs([process, *children], timeout=5)
            for child in alive:
                child.kill()
        except (psutil.Error, ValueError):
            pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manual", type=int, default=0)
    parser.add_argument("tests", nargs="*")
    args = parser.parse_args()
    pg_bin = Path(os.environ.get("PG_BIN", "C:/Program Files/PostgreSQL/18/bin"))
    initdb = shutil.which("initdb") or str(pg_bin / "initdb.exe")
    pg_ctl = shutil.which("pg_ctl") or str(pg_bin / "pg_ctl.exe")
    run = ROOT / "test-output" / ("enet-gameplay-" + secrets.token_hex(4))
    run.mkdir(parents=True)
    data = run / "postgres-data"
    temp = run / "temp"
    temp.mkdir()
    port = free_port()
    print("Isolated test artifacts:", run, flush=True)
    with (run / "setup.log").open("w") as log:
        subprocess.run([initdb, "-D", str(data), "-U", "integration", "--auth=trust",
                        "--encoding=UTF8", "--no-locale"], check=True, stdout=log, stderr=subprocess.STDOUT)
        subprocess.run([pg_ctl, "start", "-D", str(data), "-l", str(run / "postgres.log"),
                        "-o", f"-h 127.0.0.1 -p {port}", "-w"], check=True, stdout=log, stderr=subprocess.STDOUT)
    try:
        import psycopg2
        connection = psycopg2.connect(host="127.0.0.1", port=port, user="integration", dbname="postgres")
        try:
            connection.autocommit = True
            with connection.cursor() as cursor:
                cursor.execute("CREATE DATABASE wanderville_gameplay_test")
        finally:
            connection.close()
        env = dict(os.environ)
        env.update({
            "TEMP": str(temp), "TMP": str(temp),
            "PYTHONUNBUFFERED": "1",
            "WANDERVILLE_TEST_DATABASE_URL": f"postgresql+psycopg2://integration@127.0.0.1:{port}/wanderville_gameplay_test",
            "WANDERVILLE_ALLOW_TEST_RESET": "1",
            "TEST_MP_API_PORT": str(free_port()),
            "TEST_MP_PORT": str(free_port(socket.SOCK_DGRAM)),
            "WANDERVILLE_TEST_PIDFILE": str(run / "owned-pids.txt"),
            "WANDERVILLE_TEST_BACKEND_PIDFILE": str(run / "backend.pid"),
            "WANDERVILLE_TEST_KEEP_WORKDIR": "1",
            "WANDERVILLE_TEST_PROCESS_LIFETIME": str(max(600, args.manual + 180)),
        })
        if args.manual:
            env["WANDERVILLE_GAMEPLAY_MANUAL_SECONDS"] = str(args.manual)
        else:
            env.pop("WANDERVILLE_GAMEPLAY_MANUAL_SECONDS", None)
        tests = args.tests or ["tests/integration/test_enet_gameplay.py"]
        if args.manual and not args.tests:
            tests = ["tests/integration/test_enet_gameplay.py::test_two_normal_world_clients"]
        return subprocess.call([sys.executable, "-m", "pytest", "-q", "-s", "-p", "no:randomly", *tests],
                               cwd=SERVER, env=env)
    finally:
        cleanup_owned(run)
        subprocess.run([pg_ctl, "stop", "-D", str(data), "-m", "fast", "-w"],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
        print("Disposable PostgreSQL stopped.", flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
