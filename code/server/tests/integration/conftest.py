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

**Process lifetime is bounded.** Every process started here is registered in
``_OWNED``, given a maximum lifetime, and killed -- with its descendants -- by an
autouse fixture after each test. Without that, a client that never finishes leaves
a Godot process holding a UDP port, the next test waits on that port, and the
whole session degrades into timeouts rather than failures. Killing uses the
registered PID and verifies that PID is one of ours before touching it, so a
user's Godot editor or database is never a target.
"""

import json
import os
import re
import shutil
import signal
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


# ── owned-process lifecycle ────────────────────────────────────────────────
#
# Every backend, server and client this module starts is recorded here so it can
# be bounded and killed. Three properties matter, and each exists because its
# absence caused a hang:
#
#  * a maximum lifetime, so a process that stops responding is killed rather than
#    waited on;
#  * an explicit registry, so nothing is killed by name or by port. A user's
#    Godot editor, their database and any unrelated process are never touched --
#    only PIDs this harness itself created;
#  * cleanup on every path, including failures, via an autouse fixture, because
#    pytest-timeout's thread method can terminate pytest without running
#    teardown and would otherwise leave Godot processes behind.

#: Hard cap on how long any single spawned process may live.
PROCESS_LIFETIME_SECONDS = float(os.environ.get("WANDERVILLE_TEST_PROCESS_LIFETIME", "180"))

#: How long a server may take to report a listening port. Generous, because the
#: campus collision world is built before the socket is created, but finite.
SERVER_READY_TIMEOUT = float(os.environ.get("WANDERVILLE_TEST_READY_TIMEOUT", "90"))

#: How long a backend may take to become healthy.
BACKEND_READY_TIMEOUT = float(os.environ.get("WANDERVILLE_TEST_BACKEND_TIMEOUT", "90"))

#: pid -> {"process": Popen, "label": str, "started": monotonic}
_OWNED: dict[int, dict] = {}

#: Written so an external watchdog can clean up if pytest is killed abruptly.
_PIDFILE = Path(
    os.environ.get(
        "WANDERVILLE_TEST_PIDFILE",
        str(Path(os.environ.get("TEMP", ".")) / "wanderville_test_pids.txt"),
    )
)


def _write_pidfile() -> None:
    """Publish owned PIDs for the external watchdog."""
    try:
        _PIDFILE.write_text(
            " ".join(str(pid) for pid in _OWNED), encoding="utf-8"
        )
    except OSError:
        pass


def _register(process: subprocess.Popen, label: str, persistent: bool = False) -> subprocess.Popen:
    _OWNED[process.pid] = {
        "process": process,
        "label": label,
        "started": time.monotonic(),
        "persistent": persistent,
    }
    _write_pidfile()
    return process


def _kill_tree(pid: int) -> None:
    """Kill a process and its descendants, but only if it is one of ours.

    psutil is used rather than taskkill so the parentage is verified in Python
    first: a PID that has been recycled by the operating system would otherwise
    point at somebody else's process.
    """
    try:
        import psutil
    except ImportError:
        psutil = None

    if psutil is not None:
        try:
            parent = psutil.Process(pid)
            children = parent.children(recursive=True)
        except psutil.Error:
            children = []
        else:
            for child in children:
                try:
                    child.kill()
                except psutil.Error:
                    pass
    try:
        os.kill(pid, signal.SIGTERM)
    except (OSError, ProcessLookupError):
        pass
    # Give the tree a moment, then insist.
    deadline = time.monotonic() + 3.0
    while time.monotonic() < deadline:
        if not _pid_alive(pid):
            return
        time.sleep(0.1)
    try:
        if _pid_alive(pid):
            os.kill(pid, signal.SIGKILL if hasattr(signal, "SIGKILL") else signal.SIGTERM)
    except (OSError, ProcessLookupError, AttributeError):
        pass


def _pid_alive(pid: int) -> bool:
    try:
        import psutil

        return psutil.pid_exists(pid) and psutil.Process(pid).status() != psutil.STATUS_ZOMBIE
    except ImportError:
        return False
    except Exception:  # noqa: BLE001 - liveness probe only
        return False


def _reap_all() -> None:
    """Terminate every owned per-test process and wait for it to be gone.

    Skips persistent entries. The FastAPI backend is module-scoped and is owned by
    its own fixture, not by any single test; killing it after the first test made
    every later test in the module fail with a refused connection, which looked
    exactly like a networking fault.
    """
    victims = {
        pid: record
        for pid, record in _OWNED.items()
        if not record.get("persistent")
    }
    for pid, record in victims.items():
        process: subprocess.Popen = record["process"]
        if process.poll() is None:
            try:
                process.terminate()
            except OSError:
                pass
    deadline = time.monotonic() + 5.0
    while time.monotonic() < deadline:
        if all(r["process"].poll() is not None for r in victims.values()):
            break
        time.sleep(0.1)
    for pid, record in victims.items():
        process: subprocess.Popen = record["process"]
        if process.poll() is None:
            _kill_tree(pid)
        extra = getattr(process, "_wanderville_log", None)
        if extra:
            handle = extra[0]
            if not handle.closed:
                try:
                    handle.flush()
                    handle.close()
                except (OSError, ValueError):
                    pass
        _OWNED.pop(pid, None)
    _write_pidfile()


def enforce_lifetimes() -> None:
    """Kill any owned process that has outlived its maximum lifetime.

    Persistent processes -- the module-scoped backend -- get a much longer budget.
    They are meant to live for a whole module, so applying the per-test lifetime to
    them killed the backend mid-suite and every later test failed with a refused
    connection.
    """
    now = time.monotonic()
    for pid, record in list(_OWNED.items()):
        budget = PROCESS_LIFETIME_SECONDS * 4 if record.get("persistent") else PROCESS_LIFETIME_SECONDS
        if now - record["started"] < budget:
            continue
        print(
            f"\n[lifecycle] killing {record['label']} (pid {pid}): exceeded "
            f"{budget:.0f}s"
        )
        _kill_tree(pid)
        _OWNED.pop(pid, None)
    _write_pidfile()


@pytest.fixture(autouse=True)
def _bounded_processes():
    """Bound every spawned process, whatever the test does."""
    enforce_lifetimes()
    try:
        yield
    finally:
        _reap_all()
        # Let the OS and the graphics driver actually release a terminated Godot
        # process before the next test starts three more. Without this the module
        # degraded partway through: later clients failed to start or never
        # reported, which reads exactly like a movement fault but is not one --
        # the same tests pass in isolation.
        time.sleep(1.5)


def tcp_port_is_free(port: int) -> bool:
    """True when nothing holds the TCP port.

    Separate from the UDP check and deliberately so. The API runs under uvicorn,
    which listens on TCP; the multiplayer servers listen on UDP. Checking the API
    port with the UDP probe reported a busy port as free, so an orphaned backend
    from an earlier run went undetected, a fresh backend failed to bind, and the
    health probe then succeeded against the *stale* server. Every test after that
    ran against the wrong process -- a different in-memory ticket registry and a
    different host secret -- which presented as mysterious cross-test failures.
    """
    import socket as _socket

    with _socket.socket(_socket.AF_INET, _socket.SOCK_STREAM) as probe:
        probe.setsockopt(_socket.SOL_SOCKET, _socket.SO_REUSEADDR, 1)
        try:
            probe.bind((HOST, port))
            return True
        except OSError:
            return False


#: Where a started backend records its pid, so a later session can clear a backend
#: this harness orphaned rather than silently attaching to it.
_BACKEND_PIDFILE = Path(
    os.environ.get(
        "WANDERVILLE_TEST_BACKEND_PIDFILE",
        str(Path(os.environ.get("TEMP", ".")) / "wanderville_test_backend.pid"),
    )
)


def _reap_orphaned_backends() -> None:
    """Clear a backend a previous run left holding the API port.

    Only kills a process this harness recorded, and only after verifying it is
    still a uvicorn for this application -- so a recycled pid, a developer's own
    server, or the real application are never touched.
    """
    try:
        import psutil
    except ImportError:
        return
    try:
        recorded = int(_BACKEND_PIDFILE.read_text(encoding="utf-8").strip())
    except (OSError, ValueError):
        return
    try:
        process = psutil.Process(recorded)
        cmdline = " ".join(process.cmdline()).lower()
    except Exception:  # noqa: BLE001 - liveness/identity probe only
        return
    if "uvicorn" not in cmdline or "app.main:app" not in cmdline:
        # The pid was recycled by something unrelated. Leave it alone.
        return
    print(f"[harness] clearing orphaned backend pid {recorded} from a previous run")
    _kill_tree(recorded)


def listeners_on_tcp(port: int) -> list:
    """PIDs listening on a TCP port, for a diagnosable skip message."""
    try:
        import psutil
    except ImportError:
        return []
    found = []
    for connection in psutil.net_connections(kind="inet"):
        if connection.laddr and connection.laddr.port == port and connection.pid:
            found.append(connection.pid)
    return sorted(set(found))


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

    def ensure_accounts(self, names=None) -> None:
        """Create the named accounts while the rate-limit budget is fresh.

        Signup is limited to 10 per minute per IP and that limit is left in
        force, so this must never be handed the whole pool: creating fifteen
        accounts at once exhausts the budget and every later attempt waits out a
        backoff. Callers pass the few accounts they need, and because these
        modules carry the ``preserve_rows`` marker the rows survive between tests,
        so an account is signed up once for a whole session rather than per test.
        """
        global _ACCOUNTS, _VALIDATED_AT
        for name in (names or []):
            if name in _ACCOUNTS:
                continue
            record = make_account(name)
            _ACCOUNTS[name] = record
            _VALIDATED_AT[name] = time.monotonic()

    def start(self):
        # An orphaned backend from an earlier run would keep the port and answer
        # with a different host secret, which looks exactly like "invalid host
        # credentials" from the Godot side. Clear our own leftovers, then refuse
        # rather than silently test against somebody else's server.
        _reap_orphaned_backends()
        # Check the port with the protocol the API actually uses.
        if not tcp_port_is_free(API_PORT):
            owners = listeners_on_tcp(API_PORT)
            pytest.skip(
                f"TCP {API_PORT} is already held (pid {owners}). That is almost "
                "always a backend left behind by an earlier run; stop it before "
                "running this suite. Attaching to it would run these tests against "
                "a stale process with the wrong ticket registry and host secret."
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
        # Persistent: module-scoped, owned by its own fixture's teardown.
        _register(self.process, "fastapi-backend", persistent=True)
        try:
            _BACKEND_PIDFILE.write_text(str(self.process.pid), encoding="utf-8")
        except OSError:
            pass
        deadline = time.monotonic() + BACKEND_READY_TIMEOUT
        last_error = "no attempt"
        while time.monotonic() < deadline:
            if self.process.poll() is not None:
                self.stop()
                pytest.skip("backend exited during startup")
            try:
                with urllib_request(self.url + "/health") as response:
                    if response.status == 200:
                        # Confirm the server answering is *ours*. Without this the
                        # health probe can succeed against a stale backend that
                        # still owns the port, while our own uvicorn silently
                        # failed to bind and is on its way out.
                        if self.process.poll() is not None:
                            self.stop()
                            pytest.skip(
                                "our backend exited during startup; another process "
                                f"is already serving TCP {API_PORT}"
                            )
                        return self
                last_error = f"status {response.status}"
            except Exception as exc:  # noqa: BLE001 - diagnostics only
                last_error = f"{type(exc).__name__}: {exc}"
            time.sleep(0.5)
        self.stop()
        pytest.skip(
            f"backend did not become healthy within {BACKEND_READY_TIMEOUT:.0f}s "
            f"(last probe: {last_error})"
        )

    def stop(self):
        if self.process and self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                _kill_tree(self.process.pid)
                try:
                    self.process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    pass
        if self.process is not None:
            _OWNED.pop(self.process.pid, None)
            _write_pidfile()
        try:
            if _BACKEND_PIDFILE.exists():
                _BACKEND_PIDFILE.unlink()
        except OSError:
            pass
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
VALIDATION_INTERVAL = 300.0




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


def _post_with_retry(request, label: str, attempts: int = 6):
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
            # The limiter uses a 60 second window, so a short retry cannot help
            # until the window rolls over. Bounded, and only paid when actually
            # limited: making the suite faster concentrated a dozen signups into a
            # few seconds, which is what crossed the 10-per-minute budget.
            time.sleep(10 + attempt * 3)
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
    _register(process, f"godot-server:{port}")
    deadline = time.monotonic() + SERVER_READY_TIMEOUT
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise AssertionError(
                "the dedicated server exited during startup:\n" + tail(log.read_bytes())
            )
        if ready.exists() and ready.read_text(encoding="utf-8").strip():
            return process
        time.sleep(0.3)
    reap(process)
    raise AssertionError(
        "the dedicated server never reported a listening port on udp/"
        f"{port} within {SERVER_READY_TIMEOUT:.0f}s:\n" + tail(log.read_bytes())
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
    _register(process, f"client:{account['username']}")
    return process


def reap(process: subprocess.Popen, timeout: float = 15.0) -> bytes:
    """Terminate a process and return whatever it wrote, for diagnostics.

    Safe to call more than once, so a test may collect a client and then reap it
    without leaking a file handle or erroring. Bounded on every path: a process
    that ignores terminate() is killed by PID, with its descendants, rather than
    waited on.
    """
    extra = getattr(process, "_wanderville_log", None)
    if extra:
        # Flush before waiting, so a block-buffered RESULT is on disk even if the
        # process is terminated rather than exiting on its own.
        handle = extra[0]
        if not handle.closed:
            try:
                handle.flush()
            except (OSError, ValueError):
                pass
    if process.poll() is None:
        try:
            process.terminate()
        except OSError:
            pass
        try:
            process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            _kill_tree(process.pid)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                pass
    if not getattr(process, "_wanderville_persistent", False):
        _OWNED.pop(process.pid, None)
        _write_pidfile()
    if extra:
        handle, path = extra
        if not handle.closed:
            try:
                handle.close()
            except (OSError, ValueError):
                pass
        try:
            return path.read_bytes()
        except OSError:
            return b""
    return b""


def tail(data: bytes, limit: int = 1200) -> str:
    return data.decode("utf-8", "replace")[-limit:]


def collect(process: subprocess.Popen, timeout: float = 45.0) -> tuple[int, bytes]:
    """Wait for a process to exit on its own and return its captured output.

    Clients and the server write to files rather than pipes, so the output is
    read back from the file after exit. Reading a pipe instead would race the
    block buffer and report an empty result for a client that did print one.

    Bounded, and it kills rather than hanging: an unbounded wait here is what
    turned a stuck client into a hung test session.
    """
    try:
        process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        return (process.returncode or -9), reap(process)
    _OWNED.pop(process.pid, None)
    _write_pidfile()
    extra = getattr(process, "_wanderville_log", None)
    if extra:
        handle, path = extra
        if not handle.closed:
            try:
                handle.flush()
                handle.close()
            except (OSError, ValueError):
                pass
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

#: The exported campus, the same file the backend and CampusCollision use.
CAMPUS_GEOMETRY = json.loads((SERVER / "app/modules/world/geometry.json").read_text())

#: The campus spawn the server and clients both use, read from the export of
#: world.tscn so it cannot drift from CampusCollision.CAMPUS_SPAWN.
CAMPUS_SPAWN = tuple(CAMPUS_GEOMETRY["spawn"])

#: MovementAuthority.SPEED, which is the same 300 units/second the single-player
#: controllers use.
MOVEMENT_SPEED = 300.0


def movement_env(workdir: Path, arena: bool = True) -> dict:
    """Environment that makes the server write its own view of the world.

    Tests assert against the dump rather than against a client's claim, so a test
    cannot pass by believing the client that is being tested.

    ``arena`` defaults to True. That default is deliberate: the arena costs a
    fraction of a second to build while loading the real campus costs roughly 15
    seconds and about 10 MB of TileSet error output per process, and a client
    stuck in that load looks exactly like a hung test. Making the cheap world the
    default means a test only pays for the campus when it says so, and the flag
    reaches server and clients together through this one helper.
    """
    env = {
        "GODOT_MOVEMENT_ENABLED": "1",
        "GODOT_MOVEMENT_DUMP_FILE": str(workdir / "movement-dump.json"),
        "GODOT_MOVEMENT_COLLISION_FILE": str(workdir / "collision.json"),
    }
    if arena:
        env["GODOT_MOVEMENT_ARENA"] = "1"
    # Optional server-side movement diagnostics, requested from the environment so
    # a single failing test can be traced without editing the suite.
    if os.environ.get("GODOT_MOVEMENT_TRACE") == "1":
        env["GODOT_MOVEMENT_TRACE"] = "1"
    return env


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
    arena: bool = True,
    role: str = "A",
    run_id: str = "",
) -> subprocess.Popen:
    """A headless campus-movement client.

    ``input_script`` is a comma-separated ``direction:seconds`` timeline, so a
    test drives real keyboard-equivalent input through the real client rather
    than poking the server directly.

    ``arena`` defaults to True and is applied here as well as in ``movement_env``,
    because a client must build the same collision world the server simulates
    against. Setting it in one place per call site let a client silently load the
    real campus while its server uses the arena; the client then spent its whole
    startup instantiating map.tscn and emitting TileSet errors, which presented
    as a hung test rather than as a configuration mistake.

    ``role`` and ``run_id`` name the log file. The log is opened ``wb``, so two
    clients resolving to one filename means the second silently truncates and
    overwrites the first -- after which results are attributed to whichever
    process wrote last. Keying on username alone is therefore only safe while no
    test runs one account twice, which the reconnect test does.
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
        "TEST_RUN_ID": run_id or f"pid{os.getpid()}",
        "TEST_ROLE": role,
        "TEST_WORKDIR": str(workdir),
    })
    if extra_env:
        env.update(extra_env)
    if arena:
        env.setdefault("GODOT_MOVEMENT_ARENA", "1")
    else:
        env.pop("GODOT_MOVEMENT_ARENA", None)
    # Role and run id in the filename, so two clients can never share a log even
    # when they deliberately share an account.
    log = workdir / f"mover-{run_id or 'run'}-{role}-{account['username']}.log"
    handle = open(log, "wb")
    process = subprocess.Popen(
        [GODOT, "--headless", "--path", str(CLIENT), MOVEMENT_SCENE],
        cwd=str(CLIENT), env=env, stdout=handle, stderr=subprocess.STDOUT,
    )
    process._wanderville_log = (handle, log)  # type: ignore[attr-defined]
    _register(process, f"mover:{account['username']}")
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
        # Kept on request. Client and server logs are the only evidence of what a
        # Godot process actually did, and they live in this directory -- so a
        # failure is unreproducible-by-inspection unless they survive.
        if os.environ.get("WANDERVILLE_TEST_KEEP_WORKDIR") == "1":
            print(f"\n[harness] kept {directory}")
        else:
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
