"""Real two-peer ENet authentication integration test.

Nothing here is mocked. It starts an isolated FastAPI backend, starts a headless
Godot dedicated server as a separate OS process, then starts two Godot test
clients as two more separate processes. Each client opens a real UDP socket to
the server, requests a real ticket from FastAPI, and presents it.

Each client prints one ``RESULT {...}`` line, which is parsed here.

The process, port, file and rate-limit handling live in ``conftest.py`` because
the movement and rendered suites assert against exactly the same infrastructure
and must not grow a second, subtly different copy.

Skipped (not failed) when the Godot executable or the local PostgreSQL instance
is unavailable, because an environment that cannot run the test must not be
reported as a passing integration test.
"""

import json
import os
import subprocess
import time

import pytest

from conftest import (  # noqa: F401  (fixtures are resolved by pytest from conftest)
    API_URL,
    CLIENT,
    CLIENT_SCENE,
    GODOT,
    HOST,
    account,
    collect,
    diagnose,
    free_port_is_free,
    parse_result,
    reap,
    requires_godot,
    start_client,
    start_server,
    tail,
)

pytestmark = requires_godot


def test_server_starts_and_listens(backend, freed_ports, server_port, harness_dir):
    """The headless server must bind the configured UDP port.

    Readiness is taken from the server's own ready file rather than a sleep, and
    the port is re-probed to confirm something is genuinely bound.
    """
    server, _ = start_server(backend.secret, server_port, harness_dir)
    try:
        assert server.poll() is None, "the dedicated server exited during startup"
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

    server, _ = start_server(backend.secret, server_port, harness_dir)
    client_one = start_client(one, backend.secret, server_port, harness_dir, hold=8.0)
    client_two = start_client(two, backend.secret, server_port, harness_dir, hold=8.0)

    try:
        result_one = parse_result(collect(client_one)[1])
        result_two = parse_result(collect(client_two)[1])
        if result_one is None or result_two is None:
            raise AssertionError(
                "a client produced no RESULT line.\n"
                + diagnose(server, [client_one, client_two])
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
    server, _ = start_server(backend.secret, server_port, harness_dir)
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
    server, _ = start_server(backend.secret, server_port, harness_dir)

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

    server, _ = start_server(backend.secret, server_port, harness_dir)
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
        # Admitted at most once, counted on the admission line itself rather than
        # on the bare id, which later subsystems also log.
        admissions = [line for line in text.splitlines() if "admitted peer" in line]
        assert len(admissions) <= 1, text[-1500:]
    finally:
        reap(server)


def test_invalid_token_is_rejected(backend, freed_ports, server_port, harness_dir):
    """A forged access token must never reach, let alone pass, admission.

    The client retries a refused ticket with backoff before it reports a final
    rejection, so it is given the whole retry window and the test waits for the
    process rather than a fixed sleep.
    """
    server, _ = start_server(backend.secret, server_port, harness_dir)
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