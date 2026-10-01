"""Live process smoke on an explicitly empty disposable PostgreSQL *_test DB.

Run from code/server with the verification Python. Requires
WANDERVILLE_SMOKE_DATABASE_URL; never reads the user's DATABASE_URL.
"""

import asyncio
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import time

import httpx
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.engine import make_url
import websockets

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


def main():
    url = os.environ.get("WANDERVILLE_SMOKE_DATABASE_URL", "")
    parsed = make_url(url)
    if parsed.get_backend_name() != "postgresql" or not (parsed.database or "").endswith("_test"):
        raise SystemExit("Provide a disposable PostgreSQL *_test smoke database")
    engine = create_engine(url, hide_parameters=True)
    if inspect(engine).get_table_names():
        raise SystemExit("Smoke database must be empty; no existing database is reset")
    os.environ.update(
        DATABASE_URL=url, WANDERVILLE_ENV="test",
        JWT_SECRET_KEY=secrets.token_urlsafe(48), STARTING_AURA="0",
        FARM_CONSUME_INVENTORY="true", DEV_ALLOW_WORLD_MUTATION="false",
    )
    env = os.environ.copy()
    artifacts = ROOT / ".verification"
    artifacts.mkdir(exist_ok=True)
    report = {}
    for arguments in (("alembic", "upgrade", "head"), ("app.db.seed",)):
        result = subprocess.run([sys.executable, "-m", *arguments], cwd=ROOT,
                                env=env, capture_output=True, timeout=60)
        assert result.returncode == 0, "Migration or seed subprocess failed"
    with engine.connect() as connection:
        counts = {table: connection.scalar(text(f'SELECT count(*) FROM "{table}"'))
                  for table in inspect(engine).get_table_names()}
        clock = connection.execute(text("SELECT * FROM world_state")).all()
    result = subprocess.run([sys.executable, "-m", "app.db.seed"], cwd=ROOT,
                            env=env, capture_output=True, timeout=60)
    assert result.returncode == 0
    with engine.connect() as connection:
        for table, count in counts.items():
            assert connection.scalar(text(f'SELECT count(*) FROM "{table}"')) == count
        assert connection.execute(text("SELECT * FROM world_state")).all() == clock
    report["migration_seed"] = {"head": "0004_boolean_defaults", "tables": len(counts)-1,
                                "catalog_items": counts["item_definitions"],
                                "second_seed_duplicates": 0, "world_clock_changed": False}

    # Use the test mailbox only; no SMTP delivery and no token output.
    from app.db import model_registry  # noqa: F401
    from app.db.session import SessionLocal
    from app.modules.auth import email
    from app.modules.auth.schemas import SignupRequest
    from app.modules.auth.service import AuthService
    mailbox = []
    email.send_account_email = lambda *args: mailbox.append(args)
    password = secrets.token_urlsafe(24) + "Aa1!"
    ids = []
    with SessionLocal() as db:
        for name in ("smoke_one", "smoke_two"):
            player = AuthService(db).signup(SignupRequest(
                username=name, email=f"{name}@example.com", password=password))
            ids.append(player.id)
            AuthService(db).verify_email(mailbox[-1][2])

    api = worker = None
    with (artifacts / "api_smoke.log").open("w") as api_log, (artifacts / "worker_smoke.log").open("w") as worker_log:
        try:
            api = subprocess.Popen([sys.executable, "-m", "uvicorn", "app.main:app",
                                    "--host", "127.0.0.1", "--port", "58039",
                                    "--no-access-log"], cwd=ROOT, env=env,
                                   stdout=api_log, stderr=api_log,
                                   creationflags=subprocess.CREATE_NO_WINDOW)
            with httpx.Client(base_url="http://127.0.0.1:58039", timeout=10) as client:
                for _ in range(100):
                    try:
                        if client.get("/health").status_code == 200:
                            break
                    except httpx.ConnectError:
                        pass
                    time.sleep(0.1)
                assert client.get("/health").status_code == 200
                openapi = client.get("/openapi.json")
                assert openapi.status_code == 200
                report["http"] = {"health": 200, "openapi": 200,
                                  "paths": len(openapi.json()["paths"])}
                tokens, headers = [], []
                for name in ("smoke_one", "smoke_two"):
                    response = client.post("/auth/login", json={"username": name, "password": password})
                    assert response.status_code == 200
                    token = response.json()["data"]["access_token"]
                    tokens.append(token)
                    headers.append({"Authorization": f"Bearer {token}"})
                for header in headers:
                    for path in ("/profile", "/shop", "/housing", "/notifications", "/progression/goals"):
                        assert client.get(path, headers=header).status_code == 200
                assert client.get("/profile").status_code == 401
                assert client.post("/social/requests", headers=headers[0], json={"target_id": ids[1]}).status_code == 200
                assert client.post(f"/social/friends/{ids[0]}", headers=headers[1], json={"action": "accept"}).status_code == 200
                assert client.get(f"/social/farms/{ids[0]}", headers=headers[1]).status_code == 200
                worker = subprocess.Popen([sys.executable, "-m", "app.modules.world.worker"],
                                          cwd=ROOT, env=env, stdout=worker_log, stderr=worker_log,
                                          creationflags=subprocess.CREATE_NO_WINDOW)
                for _ in range(50):
                    with engine.connect() as connection:
                        events = connection.scalar(text("SELECT count(*) FROM world_events"))
                    if events:
                        break
                    assert worker.poll() is None, "Worker exited unexpectedly"
                    time.sleep(0.1)
                assert events == 1 and worker.poll() is None
                report["worker"] = {"separate_process": True, "scheduled_events": events}
                asyncio.run(socket_smoke(tokens, ids, client, headers))
                report["websocket"] = {"authenticated_accounts": 2, "proximity_chat": True,
                                       "movement": True, "sequence_replay": 409,
                                       "invalid_token": 401, "malformed_close": 1008,
                                       "oversized_close": 1009}
        finally:
            for process in (worker, api):
                if process is not None:
                    process.terminate()
                    process.wait(timeout=15)
            engine.dispose()
    (artifacts / "smoke_results.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))


async def receive_kind(socket, kind):
    for _ in range(30):
        reply = json.loads(await asyncio.wait_for(socket.recv(), timeout=3))
        if reply["type"] == kind:
            return reply
    raise AssertionError("Expected socket reply did not arrive")


async def socket_smoke(tokens, ids, client, headers):
    uri = "ws://127.0.0.1:58039/realtime/ws"
    async with websockets.connect(uri) as first, websockets.connect(uri) as second:
        for socket, token in zip((first, second), tokens):
            await socket.send(json.dumps({"type": "auth", "token": token}))
            assert (await receive_kind(socket, "snapshot"))["data"]["players"]
        await first.send(json.dumps({"type": "move", "data": {"x": 7377, "y": -891, "sequence": 1}}))
        await receive_kind(first, "snapshot")
        await first.send(json.dumps({"type": "move", "data": {"x": 7377, "y": -891, "sequence": 1}}))
        assert (await receive_kind(first, "error"))["status"] == 409
        await first.send(json.dumps({"type": "chat", "data": {"body": "Live nearby message"}}))
        for _ in range(30):
            reply = await receive_kind(second, "snapshot")
            if any(message["body"] == "Live nearby message" for message in reply["data"]["messages"]):
                break
        else:
            raise AssertionError("Nearby message was not delivered")
        assert {p["player_id"] for p in reply["data"]["players"]} == set(ids)
    async with websockets.connect(uri) as socket:
        await socket.send(json.dumps({"type": "auth", "token": "invalid"}))
        assert (await receive_kind(socket, "error"))["status"] == 401
    for payload, code in (("{", 1008), ("x" * 8193, 1009)):
        async with websockets.connect(uri) as socket:
            await socket.send(payload)
            try:
                await socket.recv()
            except websockets.ConnectionClosed as error:
                assert error.code == code
            else:
                raise AssertionError("Bad packet was accepted")


if __name__ == "__main__":
    main()
