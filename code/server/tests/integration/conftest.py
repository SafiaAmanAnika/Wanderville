"""Shared infrastructure for the real-process Godot multiplayer integration tests.

Everything here starts *real* processes: an isolated FastAPI on its own port
against the disposable local test database, a headless Godot dedicated server,
and Godot clients as further OS processes. Nothing is mocked, because the
properties under test -- UDP delivery, SceneMultiplayer authentication, server
physics, collision -- only exist at runtime.

The Windows-specific lessons recorded in the previous milestone are preserved
here deliberately, because each was paid for with a confusing failure:

* The Godot server's stdout must go to a **file**. Piping it stops Godot from
  starting at all on Windows -- it prints the engine banner and never reaches
  ``_ready``.
* Redirected output is block-buffered, so a "listening" line is not observable
  through a pipe anyway. The server therefore also writes that line to
  ``GODOT_MULTIPLAYER_READY_FILE``, written and closed immediately.
* A terminated Godot process holds its UDP port for a moment, so every test takes
  its own port, probed by actually binding it.
* Windows writes CRLF, so a bare ``$`` never matches a RESULT line even when the
  client printed one.
* Signup is rate limited per IP in the backend process, and that limit is left in
  force: accounts are created once per module and 429s are waited out.
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
RENDERED_SCENE = "res://Scenes/network/RenderedClient.tscn"
MOVEMENT_SCENE = "res://Scenes/network/MovementHarness.tscn"
HOST = "127.0.0.1"

PORT = int(os.environ.get("TEST_MP_PORT", "24567"))
API_PORT = int(os.environ.get("TEST_MP_API_PORT", "8123"))
API_URL = f"http://{HOST}:{API_PORT}"
EVIDENCE = REPO / "test-output"

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
requires_godot = pytest.mark.skipif(
    GODOT is None, reason="Godot executable not available; cannot run real-process ENet test"
)


def free_port_is_free(port: int) -> bool:
    """True when nothing holds the UDP port.

    Probed by actually binding it, which is the only reliable answer on Windows:
    a prior Godot process can hold the port for a moment after terminate(), and
    that would otherwise be mistaken for a handshake fault.
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
        self._log = None

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

    def _log_handle(self):
        """Open the backend's stderr once, so host-auth diagnostics are visible."""
        if self._log is None:
            path = Path(os.environ.get("TEMP", ".")) / "wanderville_mp_api.log"
            self._log = open(path, "ab")
        return self._log

    def start(self):
        # An orphaned backend from an earlier run would keep the port and answer
        # with a different host secret, which looks exactly like "invalid host
        # credentials" from the Godot side. Refuse rather than silently test
        # against somebody else's server.
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
            stdout=subprocess.DEVNULL, stderr=self._log_handle(),
        )
        deadline = time.time() + 60
        last_error = "no attempt"
        while time.time() < deadline:
            if self.process.poll() is not None:
                self.stop()
                pytest.skip("backend exited during startup")
            try:
                with urllib_request(self.url + "/health") as response:
                    if response.status == 200:
                        return self
                last_error = f"status {response.status}"
            except Exception as exc:  # noqa: BLE001 - diagnostics only
                last_error = f"{type(exc).__name__}: {exc}"
            time.sleep(0.5)
        self.stop()
        pytest.skip(f"backend did not become healthy in time (last probe: {last_error})")

    def stop(self):
        if self.process and self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.process.kill()
        if self._log is not None and not self._log.closed:
            self._log.close()
            self._log = None


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
#: account name -> monotonic time of its last liveness check
_VALIDATED_AT: dict[str, float] = {}
#: A cached account is trusted for this long before being re-checked.
VALIDATION_INTERVAL = 20.0


def account(username: str) -> dict:
    """A logged-in test account, created once and reused while it stays valid.

    Two constraints shape this.

    * An autouse fixture in ``tests/conftest.py`` empties the test database
      before *every* test, so an account created by an earlier test in the same
      session is gone by the next one. Reusing a cached token blindly therefore
      fails with a 401 halfway through a module.
    * The backend rate limits every auth endpoint per IP, and those limits are
      deliberately left in force. So the liveness check is throttled, and a 429
      is treated as "probably still fine" -- treating it as "invalid" would demand
      a fresh signup, which would need more rate-limited calls, which would 429
      again. That feedback loop is what made a whole module cascade.
    """
    cached = _ACCOUNTS.get(username)
    if cached is not None:
        last = _VALIDATED_AT.get(username, 0.0)
        if time.monotonic() - last < VALIDATION_INTERVAL:
            return cached
        if _token_is_valid(cached):
            _VALIDATED_AT[username] = time.monotonic()
            return cached
    _ACCOUNTS[username] = make_account(username)
    _VALIDATED_AT[username] = time.monotonic()
    return _ACCOUNTS[username]


def _token_is_valid(record: dict) -> bool:
    """Whether the cached access token still resolves to an account.

    A cheap authenticated call rather than a decode, so a token signed with a
    different secret is caught as well as one whose account no longer exists.
    """
    import urllib.error

    try:
        _get_with_token("/auth/me", record["token"])
        return True
    except urllib.error.HTTPError as exc:
        # 429 means the answer is unknown, not that the token is bad.
        return exc.code == 429
    except Exception:  # noqa: BLE001 - diagnostics only
        return False


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

    If the username already exists, signup is refused and the account is logged
    into instead. Both are the real endpoints; neither bypasses a limit or skips
    verification.
    """
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
    try:
        _post_with_retry(request, "signup")
    except urllib.error.HTTPError as exc:
        if exc.code != 400:
            raise
        # Already registered: fall through and log into the existing account.
    login = urllib.request.Request(
        API_URL + "/auth/login",
        data=json.dumps({"username": username, "password": "Strong-Pass123!"}).encode(),
        headers={"Content-Type": "application/json"}, method="POST",
    )
    tokens = _post_with_retry(login, "login")["data"]
    token = tokens["access_token"]
    # The player id is only known from signup when the account was brand new, so
    # it is read back from the profile. Tests correlate identities against this,
    # and it must never be a placeholder.
    me = _get_with_token("/auth/me", token)
    return {
        "username": username,
        "player_id": int(me["data"]["id"]),
        "token": token,
    }


def _get_with_token(path: str, token: str) -> dict:
    import urllib.request

    request = urllib.request.Request(
        API_URL + path, headers={"Authorization": "Bearer " + token}
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        return json.loads(response.read())


def start_server(
    secret: str, port: int, workdir: Path, extra_env: dict | None = None
) -> subprocess.Popen:
    """Launch the headless server and wait until it is actually listening."""
    ready = workdir / "ready.txt"
    if ready.exists():
        ready.unlink()
    env = dict(os.environ)
    env.update({
        "GODOT_MULTIPLAYER_PORT": str(port),
        "GODOT_MULTIPLAYER_BIND": HOST,
        "MULTIPLAYER_BRIDGE_SECRET": secret,
        "MULTIPLAYER_BRIDGE_URL": API_URL,
        "GODOT_MULTIPLAYER_SERVER_ID": "harness-server",
        "GODOT_MULTIPLAYER_READY_FILE": str(ready),
    })
    if extra_env:
        env.update(extra_env)
    log = workdir / "server.log"
    handle = open(log, "wb")
    process = subprocess.Popen(
        [GODOT, "--headless", "--path", str(CLIENT), SERVER_SCENE],
        cwd=str(CLIENT), env=env,
        stdout=handle, stderr=subprocess.STDOUT,
    )
    process._wanderville_log = (handle, log)  # type: ignore[attr-defined]
    deadline = time.time() + 60
    while time.time() < deadline:
        if process.poll() is not None:
            raise AssertionError(
                "the dedicated server exited during startup:\n" + tail(log.read_bytes())
            )
        if ready.exists() and ready.read_text(encoding="utf-8").strip():
            return process
        time.sleep(0.4)
    reap(process)
    raise AssertionError(
        "the dedicated server never reported a listening port on udp/"
        f"{port}:\n" + tail(log.read_bytes())
    )


def start_client(
    account: dict,
    secret: str,
    port: int,
    workdir: Path,
    hold: float = 4.0,
    extra_env: dict | None = None,
) -> subprocess.Popen:
    """Launch a headless test client whose output goes to its own file."""
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
    if extra_env:
        env.update(extra_env)
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

    Safe to call more than once, so a test may collect a client and then reap it
    without leaking a file handle or erroring.
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
    """The last RESULT line, or None."""
    matches = RESULT.findall(output)
    return json.loads(matches[-1]) if matches else None


def parse_results(output: bytes) -> list[dict]:
    """Every RESULT line, in order. The rendered client reports milestones."""
    return [json.loads(match) for match in RESULT.findall(output)]


def diagnose(server, clients) -> str:
    """Assemble every owned process's output for one failure message."""
    parts = [f"--- server ---\n{tail(reap(server), 2500)}"]
    for process in clients:
        parts.append(f"--- client ---\n{tail(reap(process), 1200)}")
    return "\n".join(parts)


# ── movement helpers ───────────────────────────────────────────────────────

#: The campus spawn the server and clients both use, mirrored from
#: CampusCollision.CAMPUS_SPAWN, which reads it from world.tscn.
CAMPUS_SPAWN = (7378.0, -891.0)

#: MovementAuthority.SPEED, which is the same 300 units/second the single-player
#: controllers use.
MOVEMENT_SPEED = 300.0


def movement_env(workdir: Path) -> dict:
    """Environment that makes the server write its own view of the world.

    Tests assert against the dump rather than against a client's claim, so a test
    cannot pass by believing the client that is being tested.
    """
    return {
        "GODOT_MOVEMENT_DUMP_FILE": str(workdir / "movement-dump.json"),
        "GODOT_MOVEMENT_COLLISION_FILE": str(workdir / "collision.json"),
    }


def read_movement_dump(workdir: Path) -> dict:
    """The server's authoritative state. Fails loudly if it is missing."""
    path = workdir / "movement-dump.json"
    if not path.exists():
        raise AssertionError(
            f"the server never wrote its movement state to {path}; "
            "was GODOT_MOVEMENT_DUMP_FILE passed to start_server()?"
        )
    return json.loads(path.read_text(encoding="utf-8"))


def read_collision(worlddir: Path) -> dict:
    """The campus outline the server actually collided against."""
    path = worlddir / "collision.json"
    if not path.exists():
        raise AssertionError(f"the server never wrote its collision world to {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def point_in_polygon(x: float, y: float, polygon: list) -> bool:
    """Standard even-odd ray cast. Used to prove a player never entered a wall."""
    inside = False
    count = len(polygon)
    for index in range(count):
        x1, y1 = polygon[index]
        x2, y2 = polygon[(index + 1) % count]
        if (y1 > y) != (y2 > y):
            crossing = x1 + (y - y1) * (x2 - x1) / (y2 - y1)
            if crossing > x:
                inside = not inside
    return inside


def nearest_shape(collision: dict, point: tuple, limit: float | None = None):
    """The collision polygon whose bounds centre is closest to ``point``."""
    best = None
    best_distance = float("inf")
    for shape in collision["shapes"]:
        points = shape["points"]
        if len(points) < 3:
            continue
        xs = [p[0] for p in points]
        ys = [p[1] for p in points]
        centre = ((min(xs) + max(xs)) / 2.0, (min(ys) + max(ys)) / 2.0)
        distance = ((centre[0] - point[0]) ** 2 + (centre[1] - point[1]) ** 2) ** 0.5
        if distance < best_distance:
            best = {"points": points, "x": (min(xs), max(xs)), "y": (min(ys), max(ys)),
                    "centre": centre, "distance": distance}
            best_distance = distance
    if best is not None and limit is not None and best["distance"] > limit:
        return None
    return best


def start_movement_client(
    account: dict,
    secret: str,
    port: int,
    workdir: Path,
    input_script: str = "",
    hold: float = 1.5,
    extra_env: dict | None = None,
) -> subprocess.Popen:
    """A headless campus-movement client.

    ``input_script`` is a comma-separated ``direction:seconds`` timeline, so a
    test drives real keyboard-equivalent input through the real client rather
    than poking the server directly.
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
        "TEST_EXPECT_ROSTER": "2",
        "TEST_INPUT_SCRIPT": input_script,
        "TEST_HOLD_SECONDS": str(hold),
        # The ticket endpoint is rate limited per IP and left that way, and a
        # whole module of tests draws on one backend process. A patient retry
        # budget keeps a 429 from being mistaken for a movement failure.
        "GODOT_MULTIPLAYER_MAX_RETRIES": "8",
    })
    if extra_env:
        env.update(extra_env)
    log = workdir / f"mover-{account['username']}.log"
    handle = open(log, "wb")
    process = subprocess.Popen(
        [GODOT, "--headless", "--path", str(CLIENT), MOVEMENT_SCENE],
        cwd=str(CLIENT), env=env, stdout=handle, stderr=subprocess.STDOUT,
    )
    process._wanderville_log = (handle, log)  # type: ignore[attr-defined]
    return process


def observed(results: list[dict], player_id: int) -> dict | None:
    """The range of positions the *server* published for one player."""
    for entry in results:
        if entry.get("event") == "final":
            for row in entry.get("observed", []):
                if int(row.get("player_id", 0)) == player_id:
                    return row
    return None


def events(results: list[dict], name: str) -> list[dict]:
    return [entry for entry in results if entry.get("event") == name]


# ── fixtures ───────────────────────────────────────────────────────────────


@pytest.fixture
def freed_ports():
    """Wait for the multiplayer UDP port to be free again between tests.

    A terminated Godot process holds its port for a moment. Without this the next
    test races against the previous test's still-bound port, which reads exactly
    like a handshake bug.

    The wait is bounded and generous, and the fixture's real job is only to keep
    a *previous* test's server from being mistaken for this one's. Each test still
    takes its own port from ``server_port``, probed by binding it.
    """
    deadline = time.time() + 60
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
    or appear in its assertions.
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