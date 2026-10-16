"""Real two-peer ENet integration test.

Nothing here is mocked. It starts an isolated FastAPI backend, starts a headless
Godot dedicated server as a separate OS process, then starts two Godot test
clients as two more separate processes. Each client opens a real UDP socket to
the server, requests a real ticket from FastAPI, and presents it.

Each client prints one ``RESULT {...}`` line, which is parsed here.

Skipped (not failed) when the Godot executable or the local PostgreSQL instance
is unavailable, because an environment that cannot run the test must not be
reported as a passing integration test.
"""

import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[4]  # repository root, above code/
CLIENT = REPO / "code" / "client"
SERVER = REPO / "code" / "server"
SERVER_SCENE = "res://Scenes/network/DedicatedServer.tscn"
CLIENT_SCENE = "res://Scenes/network/TestHarness.tscn"
HOST = "127.0.0.1"

PORT = int(os.environ.get("TEST_MP_PORT", "24567"))
API_PORT = int(os.environ.get("TEST_MP_API_PORT", "8123"))
API_URL = f"http://{HOST}:{API_PORT}"
READY_FILE = Path(
    os.environ.get(
        "TEST_MP_READY",
        str(Path(os.environ.get("TEMP", ".")) / "wanderville_mp_ready.txt"),
    )
)
API_LOG = Path(os.environ.get("TEMP", ".")) / "wanderville_mp_api.log"
_API_LOG_HANDLE = None


def _api_log_handle():
    """Open the backend's stderr once, so host-auth diagnostics are visible."""
    global _API_LOG_HANDLE
    if _API_LOG_HANDLE is None:
        _API_LOG_HANDLE = open(API_LOG, "ab")
    return _API_LOG_HANDLE
# Windows writes CRLF, so a bare `$` (which anchors before \n, not before \r)
# would never match and every result would be reported as missing even though
# the client printed it.
RESULT = re.compile(rb"^RESULT (\{.*\})\r?$", re.MULTILINE)


def godot_exe() -> str | None:
    for var in ("GODOT_EXE", "TEST_GODOT_EXE"):
        value = os.environ.get(var)
        if value and Path(value).exists():
            return value
    saved = SERVER / ".local-postgres" / "godot-path.txt"
    if saved.exists():
        candidate = saved.read_text(encoding="utf-8").strip()
        if candidate and Path(candidate).exists():
            return candidate
    for name in ("godot", "godot4"):
        found = shutil.which(name)
        if found:
            return found
    return None


GODOT = godot_exe()
pytestmark = pytest.mark.skipif(
    GODOT is None, reason="Godot executable not available; cannot run two-peer ENet test"
)

def free_port_is_free(port: int) -> bool:
    """True when nothing holds the UDP port.

    Probed by actually binding it, which is the only reliable answer on
    Windows: a prior Godot process can hold the port for a moment after
    terminate(), and that would otherwise be mistaken for a handshake fault.
    """
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        try:
            probe.bind((HOST, port))
            return True
        except OSError:
            return False


class Backend:
    """An isolated FastAPI on its own port, against the local test database."""

    def __init__(self):
        self.process = None
        self.url = API_URL
        self.secret = "integration-harness-secret"

    def _env(self) -> dict:
        """Environment for a backend subprocess, pinned to the test database."""
        env = dict(os.environ)
        env["DATABASE_URL"] = os.environ.get(
            "WANDERVILLE_TEST_DATABASE_URL", env.get("DATABASE_URL", "")
        )
        env["JWT_SECRET_KEY"] = "integration-harness-jwt-secret-value-0123456789"
        env["WORLD_WORKER_ENABLED"] = "false"
        env["REQUIRE_EMAIL_VERIFICATION"] = "false"
        env["MULTIPLAYER_BRIDGE_SECRET"] = self.secret
        env["MULTIPLAYER_HOST_ALLOWLIST"] = ""
        env["WANDERVILLE_ENV"] = "test"
        return env

    def start(self):
        # An orphaned backend from an earlier run would keep the port and answer
        # with a different host secret, which looks exactly like "invalid host
        # credentials" from the Godot side. Refuse to start on a busy port rather
        # than silently test against somebody else's server.
        if not free_port_is_free(API_PORT):
            pytest.skip(
                f"port {API_PORT} is already in use by another process; "
                "stop the stale backend before running this test"
            )
        # A disposable test database has no reference data, and login refuses to
        # issue tokens without it. Seed explicitly rather than assuming it.
        seed = subprocess.run(
            [sys.executable, "-m", "app.db.seed"],
            cwd=str(SERVER), env=self._env(), capture_output=True, timeout=300,
        )
        if seed.returncode != 0:
            pytest.skip(
                "could not seed the test database: "
                + seed.stderr.decode("utf-8", "replace")[-400:]
            )
        env = self._env()
        self.process = subprocess.Popen(
            [
                sys.executable, "-m", "uvicorn", "app.main:app",
                "--host", HOST, "--port", str(API_PORT), "--log-level", "warning",
            ],
            cwd=str(SERVER), env=env,
            stdout=subprocess.DEVNULL, stderr=_api_log_handle(),
        )
        deadline = time.time() + 60
        last_error = "no attempt"
        while time.time() < deadline:
            if self.process.poll() is not None:
                out = self.process.stdout.read().decode("utf-8", "replace")
                self.stop()
                pytest.skip(f"backend exited early: {out[-800:]}")
            try:
                with urllib_request(self.url + "/health") as response:
                    if response.status == 200:
                        return self
                last_error = f"status {response.status}"
            except Exception as exc:  # noqa: BLE001 - diagnostics only
                last_error = f"{type(exc).__name__}: {exc}"
            time.sleep(0.5)
        self.stop()
        pytest.skip(
            f"backend did not become healthy in time (last probe: {last_error})"
        )

    def stop(self):
        if self.process and self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.process.kill()


def urllib_request(url: str, data: bytes | None = None, headers: dict | None = None):
    """GET or POST a URL. ``urlopen`` only accepts a headers mapping through a
    Request object, so build one whenever headers are supplied."""
    import urllib.request

    if headers or data is not None:
        request = urllib.request.Request(
            url, data=data, headers=headers or {}, method="POST" if data else "GET"
        )
        return urllib.request.urlopen(request, timeout=10)
    return urllib.request.urlopen(url, timeout=10)


_ACCOUNTS: dict[str, dict] = {}


def account(username: str) -> dict:
    """A logged-in test account, created once per module and reused.

    Signup is rate limited per IP in the backend subprocess, and that limit is
    intentionally not weakened for tests. Creating each account exactly once
    keeps the suite inside the production limit without weakening it.
    """
    if username not in _ACCOUNTS:
        _ACCOUNTS[username] = make_account(username)
    return _ACCOUNTS[username]


def _post_with_retry(request, label: str, attempts: int = 8):
    """POST, waiting out the per-IP rate limit instead of weakening it.

    A 429 here is expected: the suite creates several accounts against one
    backend process. Retrying honours the production limit exactly as a real
    client would, instead of opening a hole in it for tests.
    """
    import urllib.error
    import urllib.request

    for attempt in range(attempts):
        try:
            with urllib.request.urlopen(request, timeout=15) as response:
                return json.loads(response.read())
        except urllib.error.HTTPError as exc:
            if exc.code != 429 or attempt == attempts - 1:
                raise
            time.sleep(8 + attempt * 2)
    raise AssertionError(f"{label} never succeeded")


def make_account(username: str) -> dict:
    """Create a verified, logged-in account through the real signup flow.

    Signup is rate limited per IP in the backend subprocess and that limit is
    deliberately left in force. Rather than weakening it, this waits the limit
    window out; the whole suite needs a handful of accounts.
    """
    import time as _time
    import urllib.error
    import urllib.request

    body = json.dumps(
        {
            "username": username,
            "email": f"{username}@example.com",
            "password": "Strong-Pass123!",
        }
    ).encode()
    request = urllib.request.Request(
        API_URL + "/auth/signup", data=body,
        headers={"Content-Type": "application/json"}, method="POST",
    )
    payload = _post_with_retry(request, "signup")
    login = urllib.request.Request(
        API_URL + "/auth/login",
        data=json.dumps({"username": username, "password": "Strong-Pass123!"}).encode(),
        headers={"Content-Type": "application/json"}, method="POST",
    )
    tokens = _post_with_retry(login, "login")["data"]
    return {
        "username": username,
        "player_id": payload["data"]["id"],
        "token": tokens["access_token"],
    }


def start_server(secret: str, port: int, workdir: Path) -> tuple[subprocess.Popen, Path]:
    """Launch the headless server and wait until it is actually listening.

    Two platform quirks are handled here rather than in the server:

    * Piping this process's stdout stops Godot from starting at all on Windows
      -- it prints only the engine banner and never reaches ``_ready``. A plain
      file redirect starts normally and still leaves the log on disk.
    * stdout is block-buffered when redirected, so the server's own "listening"
      line is not observable through a pipe anyway. It therefore also writes
      that line to ``GODOT_MULTIPLAYER_READY_FILE``, written and closed
      immediately, which is what this function waits for.
    """
    ready = workdir / "ready.txt"
    if ready.exists():
        ready.unlink()
    env = dict(os.environ)
    env.update({
        "GODOT_MULTIPLAYER_PORT": str(port),
        "GODOT_MULTIPLAYER_BIND": HOST,
        "MULTIPLAYER_BRIDGE_SECRET": secret,
        # The server must be told which backend to validate tickets against.
        "MULTIPLAYER_BRIDGE_URL": API_URL,
        "GODOT_MULTIPLAYER_SERVER_ID": "harness-server",
        "GODOT_MULTIPLAYER_READY_FILE": str(ready),
    })
    server_log = workdir / "server.log"
    log_handle = open(server_log, "wb")
    process = subprocess.Popen(
        [GODOT, "--headless", "--path", str(CLIENT), SERVER_SCENE],
        cwd=str(CLIENT), env=env,
        stdout=log_handle, stderr=subprocess.STDOUT,
    )
    process._wanderville_log = (log_handle, server_log)  # type: ignore[attr-defined]
    deadline = time.time() + 60
    while time.time() < deadline:
        if process.poll() is not None:
            raise AssertionError(
                "the dedicated server exited during startup:\n" + tail(reap(process))
            )
        if ready.exists() and ready.read_text(encoding="utf-8").strip():
            return process, ready
        time.sleep(0.4)
    reap(process)
    raise AssertionError(
        "the dedicated server never reported a listening port on udp/"
        f"{port}:\\n" + tail(server_log.read_bytes())
    )


def start_client(
    account: dict,
    secret: str,
    port: int,
    workdir: Path,
    hold: float = 4.0,
) -> subprocess.Popen:
    """Launch a headless test client whose output goes to its own file.

    A file rather than a pipe, for the same reason the server uses one: piped
    output is block-buffered, so a RESULT line can still be buffered when the
    harness collects, which looks exactly like a client that never reported.
    The file is owned by this process and closed in reap().
    """
    env = dict(os.environ)
    env.update({
        "MULTIPLAYER_BRIDGE_SECRET": secret,
        "TEST_API_URL": API_URL,
        "TEST_TOKEN": account["token"],
        "TEST_USERNAME": account["username"],
        "TEST_PLAYER_ID": str(account["player_id"]),
        "TEST_HOST": HOST,
        "TEST_PORT": str(port),
        "TEST_CLIENT_HOLD_SECONDS": str(hold),
        "GODOT_MULTIPLAYER_AUTH_TIMEOUT": "10",
    })
    log = workdir / f"client-{account['username']}.log"
    handle = open(log, "wb")
    process = subprocess.Popen(
        [GODOT, "--headless", "--path", str(CLIENT), CLIENT_SCENE],
        cwd=str(CLIENT), env=env, stdout=handle, stderr=subprocess.STDOUT,
    )
    process._wanderville_log = (handle, log)  # type: ignore[attr-defined]
    return process


def reap(process: subprocess.Popen, timeout: float = 20.0) -> bytes:
    """Terminate a process and return whatever it wrote, for diagnostics.

    Safe to call more than once: the log handle is closed at most once, so a
    test may collect a client and then reap it without leaking or erroring.
    """
    extra = getattr(process, "_wanderville_log", None)
    if process.poll() is None:
        process.terminate()
    try:
        process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=timeout)
    if extra:
        handle, path = extra
        if not handle.closed:
            handle.close()
        try:
            return path.read_bytes()
        except OSError:
            return b""
    return b""


def tail(data: bytes, limit: int = 1200) -> str:
    return data.decode("utf-8", "replace")[-limit:]


def collect(process: subprocess.Popen, timeout: float = 60.0) -> tuple[int, bytes]:
    """Wait for a process to exit on its own and return its captured output.

    Clients and the server write to files rather than pipes, so the output is
    read back from the file after exit. Reading a pipe instead would race the
    block buffer and report an empty result for a client that did print one.
    """
    try:
        process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=timeout)
    extra = getattr(process, "_wanderville_log", None)
    if extra:
        handle, path = extra
        if not handle.closed:
            handle.flush()
            handle.close()
        try:
            return process.returncode, path.read_bytes()
        except OSError:
            return process.returncode, b""
    out, _ = process.communicate()
    return process.returncode, out or b""


def parse_result(output: bytes) -> dict | None:
    matches = RESULT.findall(output)
    return json.loads(matches[-1]) if matches else None


@pytest.fixture
def freed_ports():
    """Wait for the multiplayer UDP port to be free again between tests.

    Several tests run in one session, and the UDP port lingers briefly after the
    server process is terminated. Without this the next test races against the
    previous test's still-bound port, which reads exactly like a handshake bug.
    """
    deadline = time.time() + 20
    while time.time() < deadline:
        if free_port_is_free(PORT):
            return
        time.sleep(0.5)
    pytest.skip(f"udp/{PORT} is still busy after the previous test")


@pytest.fixture
def harness_dir(freed_ports):
    """A private directory per test for readiness, logs and result files.

    Without this every test shares one ready file and one server log, so a
    leftover from the previous test can satisfy the next test's readiness check
    or appear in its assertions. Each test therefore reads only its own files.
    """
    directory = Path(tempfile.mkdtemp(prefix="wanderville-mp-"))
    try:
        yield directory
    finally:
        shutil.rmtree(directory, ignore_errors=True)


@pytest.fixture
def server_port(harness_dir):
    """A free UDP port per test.

    Distinct ports per test mean a lingering server from an earlier test cannot
    be mistaken for this test's own, which is a failure mode that looks exactly
    like a broken handshake.
    """
    for candidate in range(PORT, PORT + 60):
        if free_port_is_free(candidate):
            return candidate
    pytest.skip("no free UDP port available for the harness")


@pytest.fixture(scope="module")
def backend():
    service = Backend().start()
    yield service
    service.stop()




def _diagnose(server, clients):
    """Assemble every owned process's output for one failure message."""
    parts = [f"--- server ---\n{tail(reap(server), 2500)}"]
    for process in clients:
        parts.append(f"--- client ---\n{tail(reap(process), 1200)}")
    return "\n".join(parts)


def test_server_starts_and_listens(backend, freed_ports, server_port, harness_dir):
    """The headless server must bind the configured UDP port.

    Readiness is taken from the server's own ready file rather than a sleep, and
    the port is re-probed to confirm something is genuinely bound.
    """
    server, ready = start_server(backend.secret, server_port, harness_dir)
    try:
        assert server.poll() is None, "the dedicated server exited during startup"
        assert str(server_port) in ready.read_text(encoding="utf-8"), ready.read_text()
        assert not free_port_is_free(server_port), (
            f"udp/{server_port} should be held by the running server"
        )
    finally:
        reap(server)


def test_two_real_clients_authenticate_concurrently(
    backend, freed_ports, server_port, harness_dir
):
    """Two Godot processes, two accounts, one real UDP server, admitted together.

    Both clients are launched before either is collected, so their admissions
    overlap rather than happening one after the other. The server log proves the
    overlap: both peers are admitted before either disconnects.
    """
    one = account("mp_peer_one")
    two = account("mp_peer_two")
    assert one["player_id"] != two["player_id"]

    server, _ready = start_server(backend.secret, server_port, harness_dir)
    client_one = start_client(one, backend.secret, server_port, harness_dir, hold=8.0)
    client_two = start_client(two, backend.secret, server_port, harness_dir, hold=8.0)

    try:
        result_one = parse_result(collect(client_one)[1])
        result_two = parse_result(collect(client_two)[1])
        if result_one is None or result_two is None:
            raise AssertionError(
                "a client produced no RESULT line.\n"
                + _diagnose(server, [client_one, client_two])
            )

        assert result_one["ok"], result_one
        assert result_two["ok"], result_two

        # The backend, not the client, decided both identities.
        assert result_one["player_id"] == one["player_id"], result_one
        assert result_two["player_id"] == two["player_id"], result_two
        assert result_one["player_id"] != result_two["player_id"]
        assert result_one["server_username"] == one["username"]
        assert result_two["server_username"] == two["username"]

        text = reap(server).decode("utf-8", "replace")
        # Both admissions, and both authenticated before either disconnect.
        assert text.count("admitted peer") == 2, text[-1500:]
        assert text.count("authenticated") >= 2, text[-1500:]
        first_leave = text.find("disconnected")
        assert text.rfind("admitted peer") < first_leave or first_leave == -1, (
            "both peers should be admitted before the first disconnect:\n" + text[-1500:]
        )
    finally:
        reap(server)


def test_server_log_shows_two_distinct_admissions(
    backend, freed_ports, server_port, harness_dir
):
    """Server-side admissions carry the same identities the clients reported."""
    one = account("mp_log_one")
    two = account("mp_log_two")
    server, _ready = start_server(backend.secret, server_port, harness_dir)
    a = start_client(one, backend.secret, server_port, harness_dir, hold=5.0)
    b = start_client(two, backend.secret, server_port, harness_dir, hold=5.0)
    try:
        result_a = parse_result(collect(a)[1])
        result_b = parse_result(collect(b)[1])
        text = reap(server).decode("utf-8", "replace")

        assert result_a is not None and result_a["ok"], result_a
        assert result_b is not None and result_b["ok"], result_b
        assert result_a["player_id"] == one["player_id"]
        assert result_b["player_id"] == two["player_id"]
        assert f"player {one['player_id']}" in text, text[-1200:]
        assert f"player {two['player_id']}" in text, text[-1200:]
    finally:
        reap(server)


def test_disconnect_then_reconnect_with_a_fresh_ticket(
    backend, freed_ports, server_port, harness_dir
):
    """One peer leaving must not disturb the other, and it may come back.

    This is the disconnect/reconnect half of the milestone: the surviving client
    keeps its session, and the returning client is admitted again with a
    *different* ticket.
    """
    one = account("mp_dc_one")
    two = account("mp_dc_two")
    server, _ready = start_server(backend.secret, server_port, harness_dir)

    # The long-lived client holds its session for the whole test.
    survivor = start_client(one, backend.secret, server_port, harness_dir, hold=22.0)
    first = start_client(two, backend.secret, server_port, harness_dir, hold=4.0)
    try:
        result_first = parse_result(collect(first)[1])
        assert result_first is not None and result_first["ok"], result_first
        assert result_first["player_id"] == two["player_id"]

        # Reconnect the same account. The token is reused, so the ticket is new.
        again = start_client(two, backend.secret, server_port, harness_dir, hold=5.0)
        try:
            result_again = parse_result(collect(again)[1])
            assert result_again is not None and result_again["ok"], result_again
            assert result_again["player_id"] == two["player_id"]
        finally:
            reap(again)

        # The survivor was never disconnected by the churn.
        assert survivor.poll() is None, "the surviving client was dropped"

        text = reap(server).decode("utf-8", "replace")
        # The reconnecting account is admitted twice, once per ticket.
        admissions = [
            line for line in text.splitlines()
            if "admitted peer" in line and f"player {two['player_id']} " in line
        ]
        assert len(admissions) == 2, text[-1500:]
        # The survivor was admitted once and never dropped while the other
        # client left and came back.
        survivor_admissions = [
            line for line in text.splitlines()
            if "admitted peer" in line and f"player {one['player_id']} " in line
        ]
        assert len(survivor_admissions) == 1, text[-1500:]
        assert (
            f"player {one['player_id']} disconnected" not in text
        ), "the surviving client must not be disconnected by another peer's churn"
    finally:
        reap(survivor)
        reap(server)


def test_replayed_ticket_is_rejected(backend, freed_ports, server_port, harness_dir):
    """A ticket already spent by one peer must not admit a second peer."""
    import urllib.request

    user = account("mp_replay")
    # Ask for a ticket over plain HTTP, then present the same value twice.
    body = json.dumps({}).encode()
    request = urllib.request.Request(
        API_URL + "/multiplayer/tickets",
        data=body,
        headers={
            "Content-Type": "application/json",
            "Authorization": "Bearer " + user["token"],
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        ticket = json.loads(response.read())["data"]["ticket"]

    server, _ready = start_server(backend.secret, server_port, harness_dir)
    try:
        for attempt in range(2):
            proc = subprocess.Popen(
                [GODOT, "--headless", "--path", str(CLIENT), CLIENT_SCENE],
                cwd=str(CLIENT),
                env={
                    **os.environ,
                    "MULTIPLAYER_BRIDGE_SECRET": backend.secret,
                    "TEST_API_URL": API_URL,
                    # Deliberately bypass the client so the exact ticket is used.
                    "TEST_TICKET_OVERRIDE": ticket,
                    "TEST_USERNAME": user["username"],
                    "TEST_PLAYER_ID": str(user["player_id"]),
                    "TEST_HOST": HOST,
                    "TEST_PORT": str(server_port),
                    "TEST_CLIENT_HOLD_SECONDS": "5",
                },
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            try:
                proc.wait(timeout=60)
            except subprocess.TimeoutExpired:
                proc.kill()
        text = reap(server).decode("utf-8", "replace")
        # Admitted at most once: the replay must not produce a second admission.
        assert text.count(f"player {user['player_id']}") <= 1, text[-1500:]
    finally:
        reap(server)


def test_invalid_token_is_rejected(backend, freed_ports, server_port, harness_dir):
    """A forged access token must never reach, let alone pass, admission.

    The client retries a refused ticket with backoff before it reports a final
    rejection, so it is given the whole retry window and the test waits for the
    process rather than a fixed sleep.
    """
    server, _ready = start_server(backend.secret, server_port, harness_dir)
    log = harness_dir / "client-bogus.log"
    with open(log, "wb") as handle:
        process = subprocess.Popen(
            [GODOT, "--headless", "--path", str(CLIENT), CLIENT_SCENE],
            cwd=str(CLIENT),
            env={
                **os.environ,
                "MULTIPLAYER_BRIDGE_SECRET": backend.secret,
                "TEST_API_URL": API_URL,
                "TEST_TOKEN": "not-a-real-access-token",
                "TEST_USERNAME": "bogus",
                "TEST_PLAYER_ID": "0",
                "TEST_HOST": HOST,
                "TEST_PORT": str(server_port),
                # Long enough for the client's own retry/backoff policy to run
                # to exhaustion and report a final rejection.
                "TEST_CLIENT_HOLD_SECONDS": "45",
                "GODOT_MULTIPLAYER_MAX_RETRIES": "2",
            },
            stdout=handle,
            stderr=subprocess.STDOUT,
        )
        process._wanderville_log = (handle, log)  # type: ignore[attr-defined]
    try:
        out = collect(process, timeout=90)[1]
        result = parse_result(out)
        assert result is not None, tail(out)
        assert not result["ok"], "a forged access token must not be admitted"
    finally:
        reap(server)