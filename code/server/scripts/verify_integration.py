"""Fresh checks in disposable databases and isolated Godot user directories.

Run from code/server: python scripts/verify_integration.py --postgres
or: python scripts/verify_integration.py --godot PATH_TO_GODOT [--render]
Existing application data and credentials are never edited.
"""
import argparse
import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import subprocess
import sys
import time

SERVER = Path(__file__).resolve().parents[1]
ROOT = SERVER.parents[1]
sys.path.insert(0, str(SERVER))


def run_postgres():
    import psycopg2
    from psycopg2 import sql

    # A separate temporary cluster avoids requiring privileges on the developer's
    # existing PostgreSQL server or even reading its connection credentials.
    run = SERVER / ".verification" / ("postgres_" + secrets.token_hex(4))
    run.mkdir(parents=True)
    data = run / "data"
    initdb, pg_ctl = shutil.which("initdb"), shutil.which("pg_ctl")
    if not initdb or not pg_ctl:
        raise SystemExit("Add PostgreSQL's bin directory to PATH")
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]
    print("Creating isolated PostgreSQL cluster:", run, flush=True)
    with (run / "setup.log").open("w") as output:
        subprocess.run([initdb, "-D", str(data), "-U", "integration", "--auth=trust", "--encoding=UTF8", "--no-locale"], check=True, stdout=output, stderr=subprocess.STDOUT)
        subprocess.run([pg_ctl, "start", "-D", str(data), "-l", str(run / "postgres.log"), "-o", f"-h 127.0.0.1 -p {port}", "-w"], check=True, stdout=output, stderr=subprocess.STDOUT)
    try:
        admin = psycopg2.connect(host="127.0.0.1", port=port, user="integration", dbname="postgres")
        try:
            admin.autocommit = True
            with admin.cursor() as cursor:
                cursor.execute(sql.SQL("CREATE DATABASE {}").format(sql.Identifier("wanderville_integration_test")))
        finally:
            admin.close()
        env = {**os.environ, "WANDERVILLE_TEST_DATABASE_URL": f"postgresql+psycopg2://integration@127.0.0.1:{port}/wanderville_integration_test",
               "WANDERVILLE_ALLOW_TEST_RESET": "1"}
        result = subprocess.run([sys.executable, "-m", "pytest", "-q", "--disable-warnings"], cwd=SERVER, env=env)
        return result.returncode
    finally:
        subprocess.run([pg_ctl, "stop", "-D", str(data), "-m", "fast", "-w"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)


def run_godot(binary, render, hud=False, social=False):
    run = SERVER / ".verification" / ("client_" + secrets.token_hex(4))
    run.mkdir(parents=True)
    print("Creating isolated Godot fixtures:", run, flush=True)
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]
    env = {**os.environ, "DATABASE_URL": "sqlite:///" + (run / "client_test.db").as_posix(),
           "WANDERVILLE_ENV": "test", "JWT_SECRET_KEY": secrets.token_urlsafe(48),
           "EMAIL_DELIVERY": "file", "DEV_ALLOW_WORLD_MUTATION": "false", "STARTING_AURA": "0",
           "WANDERVILLE_API_URL": f"http://127.0.0.1:{port}", "WANDERVILLE_TEST_SYNC": str(run),
           "WANDERVILLE_TEST_PASSWORD": "Integration-" + secrets.token_hex(8) + "!", "TEST_PORT": str(port)}
    for command in (("alembic", "upgrade", "head"), ("app.db.seed",)):
        subprocess.run([sys.executable, "-m", *command], cwd=SERVER, env=env, check=True, capture_output=True)
    fixture = run / "fixture_server.py"
    fixture.write_text('''import asyncio, os, sys
sys.path.insert(0, os.environ["WANDERVILLE_SERVER_ROOT"])
from app.db.session import SessionLocal
from app.modules.auth import email
from app.modules.auth.service import AuthService
from app.modules.auth.schemas import SignupRequest
from app.modules.profile.service import ProfileService
from app.modules.profile.schemas import ProfileUpdate
from app.modules.inventory.service import InventoryService
from app.modules.inventory.schemas import ItemRequest
from app.modules.notifications.service import NotificationsService
from app.db.session import transaction
from app.main import app
from app.core.responses import success
from fastapi.responses import JSONResponse
from fastapi import Depends
from app.modules.auth.dependencies import get_current_player_id
from app.modules.economy.service import EconomyService
from app.modules.players.repository import PlayerRepository
@app.post("/integration/progress/{amount}")
def progress(amount: int, pid: int = Depends(get_current_player_id)):
    with SessionLocal() as db:
        with transaction(db):
            PlayerRepository(db).lock(pid)
            EconomyService(db).gain_internal(pid, amount)
        return success({})
@app.post("/integration/stack-fixture")
def stack_fixture(pid: int = Depends(get_current_player_id)):
    with SessionLocal() as db:
        InventoryService(db).add_compatibility(pid, ItemRequest(item_code="wheat_seed", quantity=100))
        InventoryService(db).add_compatibility(pid, ItemRequest(item_code="potato_seed", quantity=2))
    return success({})
@app.post("/integration/fill-inventory")
def fill_inventory(pid: int = Depends(get_current_player_id)):
    with SessionLocal() as db:
        with transaction(db):
            PlayerRepository(db).lock(pid)
            inventory = InventoryService(db)
            summary = inventory.list(pid)
            room = sum(99 - item.quantity for item in summary.items if item.item_code == "wheat_seed")
            # Leave exactly three units of space in the last stack, no free slot.
            inventory.add_internal(pid, "wheat_seed", room + (summary.capacity - summary.used_slots) * 99 - 3)
        return success({})
app.state.lose_shop_response = False
app.state.lose_gift_response = False
@app.post("/integration/lose-next-gift-response")
async def lose_gift_response():
    app.state.lose_gift_response = True
    return success({})
@app.post("/integration/lose-next-shop-response")
async def lose_response():
    app.state.lose_shop_response = True
    return success({})
@app.middleware("http")
async def simulate_lost_response(request, call_next):
    response = await call_next(request)
    if request.url.path == "/social/gifts" and response.status_code == 200 and app.state.lose_gift_response:
        app.state.lose_gift_response = False
        return JSONResponse(status_code=503, content={"message": "Fixture lost committed gift response"})
    if request.url.path == "/shop/buy" and response.status_code == 200 and app.state.lose_shop_response:
        app.state.lose_shop_response = False
        return JSONResponse(status_code=503, content={"message": "Fixture lost committed response"})
    return response
mail = []
email.send_account_email = lambda *args: mail.append(args)
with SessionLocal() as db:
    for name in ("integration_alice", "integration_bob"):
        auth = AuthService(db)
        player = auth.signup(SignupRequest(username=name, email=name+"@example.com", password=os.environ["WANDERVILLE_TEST_PASSWORD"]))
        auth.verify_email(mail[-1][2])
        ProfileService(db).update(player.id, ProfileUpdate(character_code="player1", map_code="campus"))
        InventoryService(db).add_compatibility(player.id, ItemRequest(item_code="wheat_seed", quantity=3))
        if os.environ.get("WANDERVILLE_TEST_HUD") == "1":
            with transaction(db):
                for index in range(35):
                    NotificationsService(db).emit(player.id, "test", f"Fixture notification {index + 1}")
@app.get("/integration/delay")
async def delay():
    await asyncio.sleep(.3)
    return success({"old_session": True})
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=int(os.environ["TEST_PORT"]), access_log=False)
''', encoding="utf-8")
    env["WANDERVILLE_SERVER_ROOT"] = str(SERVER)
    env["WORLD_WORKER_ENABLED"] = "false"
    env["VOICE_ENABLED"] = "true" if social else "false"
    env["WANDERVILLE_TEST_HUD"] = "1" if hud else "0"
    log = (run / "server.log").open("w", encoding="utf-8")
    backend = subprocess.Popen([sys.executable, str(fixture)], cwd=SERVER, env=env, stdout=log, stderr=subprocess.STDOUT)
    clients, handles = [], []
    try:
        import httpx
        for _ in range(100):
            if backend.poll() is not None:
                raise RuntimeError("Fixture server failed; inspect " + str(run / "server.log"))
            try:
                if httpx.get(env["WANDERVILLE_API_URL"] + "/ready", timeout=1).status_code == 200:
                    break
            except httpx.HTTPError:
                pass
            time.sleep(.1)
        else:
            raise RuntimeError("Fixture backend readiness timed out")
        source = ROOT / "code/client"
        roles = ("alice",) if hud else ("alice", "bob")
        for role in roles:
            project = run / role
            project.mkdir()
            # Junctions share immutable source resources; each test has its own
            # project config, import cache, user directory, and output log.
            for name in ("Assets", "Scenes", "Scripts", "autoloads", "tests"):
                if os.name == "nt":
                    subprocess.run(["cmd", "/c", "mklink", "/J", str(project / name), str(source / name)], check=True, capture_output=True)
                else:
                    (project / name).symlink_to(source / name, target_is_directory=True)
            shutil.copytree(source / ".godot", project / ".godot", ignore=shutil.ignore_patterns("editor"))
            config = (source / "project.godot").read_text(encoding="utf-8")
            config = config.replace("[application]", '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="WandervilleVerification/' + run.name + '/' + role + '"')
            (project / "project.godot").write_text(config, encoding="utf-8")
            arguments = [binary, "--path", str(project), "--script", "res://tests/proximity_integration.gd" if social else ("res://tests/hud_integration.gd" if hud else "res://tests/integration.gd")]
            if render:
                arguments += ["--rendering-method", "gl_compatibility", "--position", "20000,20000"]
            else:
                arguments += ["--headless"]
            output = (run / f"{role}.log").open("w", encoding="utf-8")
            handles.append(output)
            options = {}
            if os.name == "nt":
                startup = subprocess.STARTUPINFO()
                startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
                startup.wShowWindow = 0
                options["startupinfo"] = startup
            clients.append(subprocess.Popen(arguments, env={**env, "WANDERVILLE_TEST_ROLE": role}, stdout=output, stderr=subprocess.STDOUT, **options))
        deadline = time.monotonic() + (120 if hud else 360)
        while time.monotonic() < deadline and any(p.poll() is None for p in clients):
            if any(p.poll() not in (None, 0) for p in clients):
                raise RuntimeError("A Godot test process failed; logs: " + str(run))
            time.sleep(.2)
        for process in clients:
            if process.poll() is None:
                process.terminate()
                raise RuntimeError("Godot integration timed out; logs: " + str(run))
        result = {role: process.returncode for role, process in zip(roles, clients)}
        if hud and all(value == 0 for value in result.values()):
            # A new Godot process with the same isolated user directory proves
            # restart persistence and reconciliation of a saved operation ID.
            with (run / "restart.log").open("w", encoding="utf-8") as restart_log:
                restarted = subprocess.Popen(arguments, env={**env, "WANDERVILLE_TEST_RESTART": "1"},
                                             stdout=restart_log, stderr=subprocess.STDOUT, **options)
                clients.append(restarted)
                result["restart"] = restarted.wait(timeout=60)
        (run / "result.json").write_text(json.dumps(result, indent=2))
        print("GODOT_INTEGRATION", json.dumps(result), "artifacts:", run, flush=True)
        return 0 if all(value == 0 for value in result.values()) else 1
    finally:
        for process in clients + [backend]:
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=10)
        for handle in handles + [log]:
            handle.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--postgres", action="store_true")
    parser.add_argument("--godot")
    parser.add_argument("--render", action="store_true")
    parser.add_argument("--social", action="store_true", help="Two native Godot clients: proximity, PCM voice, wishlist and gifts")
    parser.add_argument("--hud", action="store_true", help="Single-client HUD checks without loading the large map")
    args = parser.parse_args()
    if args.postgres:
        raise SystemExit(run_postgres())
    if args.godot:
        raise SystemExit(run_godot(args.godot, args.render, args.hud, args.social))
    parser.error("Choose --postgres or --godot PATH")
