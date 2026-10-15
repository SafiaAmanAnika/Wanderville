"""Start a private local PostgreSQL cluster without touching installed services.

Uses the installed PostgreSQL binaries, a password-authenticated loopback-only
cluster, and the existing Python environment. Credentials and data stay ignored.
"""

import argparse
import os
from pathlib import Path
import secrets
import shutil
import socket
import subprocess
import sys

from dotenv import dotenv_values, set_key
import psycopg2
from sqlalchemy.engine import make_url

SERVER = Path(__file__).resolve().parents[1]
LOCAL = SERVER / ".local-postgres"
DATA = LOCAL / "data"
ENV = SERVER / ".env"
PORT = 5434


def binary(name):
    found = shutil.which(name)
    if found:
        return found
    candidates = sorted(
        Path(os.environ.get("ProgramFiles", "C:/Program Files")).glob(
            f"PostgreSQL/*/bin/{name}.exe"
        ), reverse=True,
    )
    if not candidates:
        raise SystemExit("Install PostgreSQL or add its bin folder to PATH.")
    return str(candidates[0])


def run(*args):
    with (LOCAL / "setup.log").open("a", encoding="utf-8") as log:
        result = subprocess.run(args, cwd=SERVER, stdout=log, stderr=log)
    if result.returncode:
        raise SystemExit("Local setup failed; see code/server/.local-postgres/setup.log")


def start_database():
    LOCAL.mkdir(exist_ok=True)
    credentials = LOCAL / "connection.env"
    if not credentials.exists():
        if DATA.exists():
            raise SystemExit("Existing local cluster has no credential file; refusing to overwrite it.")
        credentials.write_text(
            "DATABASE_URL=postgresql+psycopg2://wanderville_local:"
            + secrets.token_urlsafe(32)
            + f"@127.0.0.1:{PORT}/wanderville_local\n", encoding="utf-8",
        )
    url = make_url(dotenv_values(credentials)["DATABASE_URL"])
    if url.host != "127.0.0.1" or url.port != PORT or url.database != "wanderville_local":
        raise SystemExit("Local connection must target 127.0.0.1:5434/wanderville_local.")
    if not (DATA / "PG_VERSION").exists():
        password_file = LOCAL / "init-password"
        try:
            password_file.write_text(url.password + "\n", encoding="utf-8")
            run(binary("initdb"), "-D", str(DATA), "-U", url.username,
                "--auth=scram-sha-256", "--encoding=UTF8", "--no-locale",
                "--pwfile=" + str(password_file))
        finally:
            password_file.unlink(missing_ok=True)
    status = subprocess.run(
        [binary("pg_ctl"), "status", "-D", str(DATA)], capture_output=True,
    )
    if status.returncode:
        with socket.socket() as listener:
            try:
                listener.bind(("127.0.0.1", PORT))
            except OSError:
                raise SystemExit("Port 5434 is in use by another service; nothing was changed.") from None
        run(binary("pg_ctl"), "start", "-D", str(DATA), "-l", str(LOCAL / "postgres.log"),
            "-o", f"-h 127.0.0.1 -p {PORT}", "-w")
    conn = psycopg2.connect(host=url.host, port=url.port, user=url.username,
                           password=url.password, dbname="postgres", connect_timeout=5)
    try:
        conn.autocommit = True
        with conn.cursor() as cur:
            cur.execute("SELECT 1 FROM pg_database WHERE datname = %s", (url.database,))
            if cur.fetchone() is None:
                cur.execute("CREATE DATABASE wanderville_local")
    finally:
        conn.close()
    return url.render_as_string(hide_password=False)


def configure(url):
    backup = SERVER / ".env.before-neon-local-fix.bak"
    if ENV.exists() and not backup.exists():
        shutil.copy2(ENV, backup)
    values = {
        "DATABASE_URL": url,
        "WANDERVILLE_ENV": "dev",
        "WANDERVILLE_HOST": "127.0.0.1",
        "WANDERVILLE_PORT": "8000",
        "WORLD_WORKER_ENABLED": "false",
        "EMAIL_DELIVERY": "file",
        "EMAIL_BASE_URL": "http://127.0.0.1:8000",
    }
    for key, value in values.items():
        set_key(str(ENV), key, value)
        # A stale inherited cloud DATABASE_URL must never override this launcher.
        os.environ[key] = value
    print("Local PostgreSQL ready at 127.0.0.1:5434/wanderville_local.", flush=True)
    print("Original environment preserved in .env.before-neon-local-fix.bak.", flush=True)
    run(sys.executable, "-m", "alembic", "upgrade", "head")
    run(sys.executable, "-m", "app.db.seed")
    print("Migrations and reference seeding complete. No Neon connection was made.", flush=True)


def lan_addresses():
    """IPv4 addresses other devices on this network could reach.

    169.254.x.x are link-local and unusable, so they are skipped; loopback,
    virtual and Bluetooth adapters are skipped because nothing on the LAN can
    route to them.
    """
    import socket
    found = set()
    try:
        probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        probe.connect(("8.8.8.8", 80))  # no packet is sent; this only picks a NIC
        found.add(probe.getsockname()[0])
        probe.close()
    except OSError:
        pass
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            address = info[4][0]
            if not address.startswith("169.254.") and not address.startswith("127."):
                found.add(address)
    except OSError:
        pass
    return sorted(found)


def serve(host, port):
    print(f"API: http://{host}:{port}", flush=True)
    if host == "0.0.0.0":
        addresses = lan_addresses()
        if addresses:
            print(
                "Share this with anyone on your network:\n  "
                + "\n  ".join(f"http://{address}:{port}" for address in addresses),
                flush=True,
            )
        print(
            "Windows Firewall may block incoming connections; allow this program "
            "on private networks when prompted.",
            flush=True,
        )
    else:
        print("Bound to localhost only. Pass --lan to let a friend connect.", flush=True)
    return subprocess.call(
        [
            sys.executable, "-m", "uvicorn", "app.main:app", "--host", host,
            "--port", str(port), "--workers", "1", "--no-access-log",
        ],
        cwd=SERVER,
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serve", action="store_true")
    parser.add_argument("--stop-db", action="store_true")
    parser.add_argument(
        "--lan",
        action="store_true",
        help="Accept connections from other devices on your network (default: localhost only).",
    )
    args = parser.parse_args()
    if args.stop_db:
        if (DATA / "postmaster.pid").exists():
            run(binary("pg_ctl"), "stop", "-D", str(DATA), "-m", "fast", "-w")
        return
    configure(start_database())
    if args.serve:
        print("Verification emails: code/server/.dev-mail", flush=True)
        raise SystemExit(serve("0.0.0.0" if args.lan else "127.0.0.1", 8000))


if __name__ == "__main__":
    main()
