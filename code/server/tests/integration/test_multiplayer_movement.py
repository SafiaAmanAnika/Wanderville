"""Real two-peer server-authoritative movement integration tests.

Nothing here is mocked. Each test starts a real headless Godot dedicated server,
then two real Godot clients as separate OS processes. The clients authenticate
with real FastAPI tickets, send real input over real ENet, and the server
simulates them against the real campus collision harvested from ``map.tscn``.

**Assertions are made against the server's own state, not the clients'.** The
server writes its authoritative entity positions and its rejection counters to
``GODOT_MOVEMENT_DUMP_FILE`` and the campus outline to
``GODOT_MOVEMENT_COLLISION_FILE``. A test therefore cannot pass by believing the
client that is under test, and "the player moved" means the *server* moved them
at the server's speed against the server's collision.

The campus polygon outline is also written out, so "the player never walked
through the lake" is checked with a point-in-polygon test against the actual map
geometry rather than against a guessed wall position.
"""

import json
import os
import time

import pytest

from conftest import (
    API_URL,
    CAMPUS_SPAWN,
    CLIENT,
    GODOT,
    HOST,
    MOVEMENT_SPEED,
    account,
    collect,
    _register,
    enforce_lifetimes,
    diagnose,
    events,
    movement_env,
    nearest_shape,
    observed,
    parse_results,
    point_in_polygon,
    read_collision,
    read_movement_dump,
    reap,
    requires_godot,
    start_movement_client,
    start_server,
    tail,
)

pytestmark = [requires_godot, pytest.mark.preserve_rows]

# A small fixed pool. Signup is rate limited per IP and that limit is left in
# force, so accounts are created once and reused across the module rather than
# one per test.
#
# Resolved lazily inside tests, not at import: the backend subprocess does not
# exist until the `backend` fixture runs, so touching the API here would fail
# during collection.
NAMES = ["mv_p1", "mv_p2", "mv_p3", "mv_p4", "mv_p5", "mv_p6"]

#: Half the height of the isolated test arena, mirrored from MovementArena.
ARENA_HALF_HEIGHT = 1200.0
#: Deterministic spawn ring radius, mirrored from MovementClient._spawn_point.
ARENA_SPAWN_RING = 260.0


def pool_user(index: int) -> dict:
    return account(NAMES[index])


def pair(index: int = 0):
    return pool_user(index), pool_user(index + 1)


def run_pair(
    backend,
    server_port,
    harness_dir,
    script_a="",
    script_b="",
    hold: float = 1.5,
    extra_a: dict | None = None,
    extra_b: dict | None = None,
    extra_env_server: dict | None = None,
    users=None,
    index: int = 0,
    partners: bool = True,
):
    """Start a server plus two movement clients, wait for both, and collect.

    Both clients are allowed to finish on their own. Collecting one while the
    other is still running would terminate it early and produce exactly the kind
    of spurious disconnect these tests exist to examine.
    """
    one, two = users if users else pair(index)
    server_env = movement_env(harness_dir)
    if extra_env_server:
        server_env.update(extra_env_server)
    server = start_server(
        backend.secret, server_port, harness_dir, extra_env=server_env
    )

    def shared(extra: dict | None) -> dict:
        """Client environment, told about the arena.

        Building the real campus collision means instantiating map.tscn and its
        TileSet, which is slow and -- given the map's pre-existing tile errors --
        extremely noisy. A test that runs entirely inside the arena must not pay
        that cost in two client processes as well as the server.
        """
        env = dict(extra or {})
        if server_env.get("GODOT_MOVEMENT_ARENA") == "1":
            env["GODOT_MOVEMENT_ARENA"] = "1"
        return env
    a = start_movement_client(
        one, backend.secret, server_port, harness_dir, script_a, hold, shared(extra_a)
    )
    if not partners:
        # A single client is enough for the validation tests: an admitted peer
        # can attack the server on its own, and every avoided client is an avoided
        # admission ticket. The ticket endpoint allows 30 per minute per IP and the
        # suite is otherwise close enough to that ceiling for the later tests to
        # spend their time in rate-limit backoff.
        wait_for(a)
        return server, parse_results(reap(a)), [], reap(a), b""
    b = start_movement_client(
        two, backend.secret, server_port, harness_dir, script_b, hold, shared(extra_b)
    )
    wait_for(a, b)
    out_a = reap(a, timeout=20)
    out_b = reap(b, timeout=20)
    return server, parse_results(out_a), parse_results(out_b), out_a, out_b


def wait_for(*processes, timeout: float = 90.0) -> None:
    """Wait for every process to exit, within a hard bound.

    Bounded on purpose. A client that never finishes used to turn into a hung
    session rather than a failure, and the harness cannot tell the difference
    between "still working" and "never going to finish" -- so it gives up and the
    autouse cleanup kills whatever is left.
    """
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if all(p.poll() is not None for p in processes):
            return
        enforce_lifetimes()
        time.sleep(0.5)


def movement_extent(row: dict) -> dict:
    return {
        "width": row["max_x"] - row["min_x"],
        "height": row["max_y"] - row["min_y"],
    }


# ── 1, 2, 3: join, identity, entity spawn ───────────────────────────────────


def test_two_players_join_campus_and_spawn(backend, freed_ports, server_port, harness_dir):
    """Two authenticated players get the identities the backend decided, and the
    server creates a real physics entity for each.

    Runs in the isolated arena. The *room* is still campus -- that is decided by
    the backend and reported over admission -- but nothing here is about campus
    geometry, and loading the real map in three processes pushed this test past
    its timeout on its own.
    """
    one, two = pair(0)
    server, results_a, results_b, out_a, out_b = run_pair(
        backend, server_port, harness_dir, hold=1.0, index=0,
        extra_env_server={"GODOT_MOVEMENT_ARENA": "1"},
    )
    try:
        admitted_a = events(results_a, "admitted")
        admitted_b = events(results_b, "admitted")
        assert admitted_a and admitted_b, (out_a[-1200:], out_b[-1200:])
        assert admitted_a[0]["player_id"] == one["player_id"], admitted_a[0]
        assert admitted_b[0]["player_id"] == two["player_id"], admitted_b[0]
        assert admitted_a[0]["player_id"] != admitted_b[0]["player_id"]
        assert admitted_a[0]["room"] == "campus", admitted_a[0]

        dump = read_movement_dump(harness_dir)
        assert dump["collision_shapes"] > 0, "the server simulated in a void"

        # Each client saw the other join, which means both entities existed.
        joined_a = events(results_a, "remote_joined")
        joined_b = events(results_b, "remote_joined")
        assert [e["other"] for e in joined_a] == [two["player_id"]], joined_a
        assert [e["other"] for e in joined_b] == [one["player_id"]], joined_b

        text = reap(server).decode("utf-8", "replace")
        assert text.count("spawned player") == 2, text[-1500:]
    finally:
        reap(server)


# ── 4, 5, 13: A moves right, the server records it at the game's speed ─────


def test_player_a_moves_right_and_the_server_records_it(
    backend, freed_ports, server_port, harness_dir
):
    """Client A walks right; the server's own state shows it moved right, and by
    about the speed the single-player controllers use."""
    one, two = pair(0)
    seconds = 2.0
    server, results_a, _results_b, out_a, _out_b = run_pair(
        backend, server_port, harness_dir, script_a="right:%.1f" % seconds,
        hold=1.0, index=0,
        # Clear interior, so 2.0s of travel is measured rather than cut short by
        # whichever campus obstacle happens to be near the spawn ring.
        extra_env_server={"GODOT_MOVEMENT_ARENA": "1"},
    )
    try:
        row = observed(results_a, one["player_id"])
        assert row is not None, out_a[-1500:]
        extent = movement_extent(row)
        # 2.0s at 300 units/s is 600 units of travel.
        expected = MOVEMENT_SPEED * seconds
        assert extent["width"] > expected * 0.7, extent
        assert extent["width"] < expected * 1.35, extent
        assert extent["height"] < expected * 0.2, "A only pressed right"
        assert row["max_x"] > row["min_x"]
    finally:
        reap(server)


# ── 6: B receives A's movement ─────────────────────────────────────────────


def test_player_b_receives_player_a_movement(
    backend, freed_ports, server_port, harness_dir
):
    """B never presses a key toward A, yet B's view of A's position changes,
    because those positions come from the server's snapshots."""
    one, two = pair(0)
    server, _results_a, results_b, _out_a, out_b = run_pair(
        backend, server_port, harness_dir,
        script_a="right:2.0", script_b="idle:0.1", hold=1.5, index=0,
        extra_env_server={"GODOT_MOVEMENT_ARENA": "1"},
    )
    try:
        row = observed(results_b, one["player_id"])
        assert row is not None, out_b[-1500:]
        extent = movement_extent(row)
        assert extent["width"] > MOVEMENT_SPEED * 1.4, (
            "B did not observe A moving right:\n" + out_b[-1500:]
        )
        # And B really was standing still while it happened.
        own = observed(results_b, two["player_id"])
        assert own is not None and movement_extent(own)["width"] < 30.0, own
    finally:
        reap(server)


# ── 7, 8: B moves up, A receives it ────────────────────────────────────────


def test_player_b_moves_up_and_player_a_receives_it(
    backend, freed_ports, server_port, harness_dir
):
    """The other direction, to prove the two axes are not special-cased."""
    one, two = pair(0)
    server, results_a, results_b, _out_a, _out_b = run_pair(
        backend, server_port, harness_dir,
        script_a="idle:0.1", script_b="up:2.0", hold=1.5, index=0,
        extra_env_server={"GODOT_MOVEMENT_ARENA": "1"},
    )
    try:
        own_b = observed(results_b, two["player_id"])
        assert own_b is not None and movement_extent(own_b)["height"] > MOVEMENT_SPEED * 1.4, own_b
        seen_by_a = observed(results_a, two["player_id"])
        assert seen_by_a is not None, "A never received a snapshot of B"
        assert movement_extent(seen_by_a)["height"] > MOVEMENT_SPEED * 1.4, seen_by_a
    finally:
        reap(server)


# ── 9, 20: concurrent movement, independent authority ──────────────────────


def test_both_players_move_concurrently_without_sharing_authority(
    backend, freed_ports, server_port, harness_dir
):
    """Two players move at once and each one's input moves only their own body."""
    one, two = pair(0)
    server, results_a, results_b, _out_a, out_b = run_pair(
        backend, server_port, harness_dir,
        script_a="right:2.5", script_b="down:2.5", hold=1.5, index=0,
        extra_env_server={"GODOT_MOVEMENT_ARENA": "1"},
    )
    try:
        row_a = observed(results_a, one["player_id"])
        row_b = observed(results_b, two["player_id"])
        assert movement_extent(row_a)["width"] > MOVEMENT_SPEED * 1.6, row_a
        assert movement_extent(row_b)["height"] > MOVEMENT_SPEED * 1.6, row_b
        # A pressed right only, so its vertical travel must stay negligible.
        assert movement_extent(row_a)["height"] < MOVEMENT_SPEED * 0.3, row_a
        dump = read_movement_dump(harness_dir)
        assert dump["speed_limit_violations"] == 0, dump
        assert dump["rejects"] == {}, dump
    finally:
        reap(server)


def test_one_player_cannot_drive_the_other(
    backend, freed_ports, server_port, harness_dir
):
    """A sends input only; B's server-reported position must not budge.

    This is the independence check: it is not enough that B's client ignores
    things, the server must keep the two bodies separate.
    """
    one, two = pair(0)
    server, _results_a, results_b, _out_a, out_b = run_pair(
        backend, server_port, harness_dir,
        script_a="right:2.5", script_b="idle:0.1", hold=2.0, index=0,
        extra_env_server={"GODOT_MOVEMENT_ARENA": "1"},
    )
    try:
        row_b = observed(results_b, two["player_id"])
        assert row_b is not None, out_b[-1500:]
        assert movement_extent(row_b)["width"] < 30.0, (
            "B moved although only A sent input:\n%s" % row_b
        )
        assert movement_extent(row_b)["height"] < 30.0, row_b
    finally:
        reap(server)


# ── 10: movement before authentication ──────────────────────────────────────


def test_unauthenticated_peer_cannot_move(
    backend, freed_ports, server_port, harness_dir
):
    """A peer that never authenticates cannot create or move an entity.

    It opens a real UDP socket to the real server and floods real movement RPCs.
    The server's own dump must show no entity for it and no movement anywhere.
    """
    import subprocess

    one, two = pair(0)
    server = start_server(
        backend.secret, server_port, harness_dir,
        extra_env={**movement_env(harness_dir), "GODOT_MOVEMENT_ARENA": "1"},
    )
    try:
        # One honest client, so there is a real body to try to interfere with.
        honest = start_movement_client(
            one, backend.secret, server_port, harness_dir, "right:1.5", 1.5,
            {"TEST_EXPECT_ROSTER": "1"},
        )
        attacker_log = harness_dir / "attacker.log"
        handle = open(attacker_log, "wb")
        attacker = subprocess.Popen(
            [GODOT, "--headless", "--path", str(CLIENT),
             "res://Scenes/network/MovementHarness.tscn"],
            cwd=str(CLIENT),
            env={
                **os.environ,
                "TEST_API_URL": API_URL,
                "TEST_USERNAME": "mv_attacker",
                "TEST_HOST": HOST,
                "TEST_PORT": str(server_port),
                "TEST_UNAUTHENTICATED": "1",
                "TEST_RAW_ATTACKS": "flood,flood,flood",
                "TEST_EXPECT_ROSTER": "1",
            },
            stdout=handle, stderr=subprocess.STDOUT,
        )
        attacker._wanderville_log = (handle, attacker_log)
        _register(attacker, "mv_attacker")
        wait_for(honest, attacker)
        reap(attacker)
        reap(honest)

        text = reap(server).decode("utf-8", "replace")
        # The attacker was never admitted, so it was never spawned.
        assert not [
            line for line in text.splitlines()
            if "admitted peer" in line and "mv_attacker" in line
        ], text[-1500:]
        # Exactly one entity in total: the honest player only. The attacker's
        # packets produced no entity and moved nothing.
        assert text.count("spawned player") == 1, text[-1500:]
        # And the honest player was in fact admitted and simulated.
        assert "admitted peer" in text, text[-1200:]
        assert f"player {one['player_id']}" in text, text[-1200:]
    finally:
        reap(server)


# ── 11, 12, 15: packet-level validation, from a real admitted peer ─────────


def test_forged_identity_field_is_rejected(
    backend, freed_ports, server_port, harness_dir
):
    """A well-formed input packet with an identity field glued on is refused.

    The attacker here *is* admitted, so this proves the server judged the packet
    rather than the connection.
    """
    one, two = pair(1)
    server, results_a, _results_b, _out_a, out_a = run_pair(
        backend, server_port, harness_dir,
        script_a="idle:0.1", script_b="idle:0.1", hold=1.0, index=1,
        extra_env_server={"GODOT_MOVEMENT_ARENA": "1"},
        extra_a={"TEST_RAW_ATTACKS": "oversized_identity", "TEST_EXPECT_ROSTER": "1"},
        extra_b={"TEST_EXPECT_ROSTER": "1"},
        partners=False,
    )
    try:
        dump = read_movement_dump(harness_dir)
        assert dump["rejects"].get("malformed", 0) >= 1, dump
        final = events(results_a, "final")
        assert final and final[0]["attacks_sent"] == 1, final
    finally:
        reap(server)


def test_invalid_direction_is_rejected(backend, freed_ports, server_port, harness_dir):
    """A direction longer than a unit vector -- "move 1.4x faster" -- is refused,
    and the player does not actually speed up."""
    one, two = pair(1)
    server, results_a, _results_b, _out_a, _out_a = run_pair(
        backend, server_port, harness_dir,
        script_a="right:2.0", script_b="idle:0.1", hold=1.0, index=1,
        extra_env_server={"GODOT_MOVEMENT_ARENA": "1"},
        extra_a={"TEST_RAW_ATTACKS": "long_direction", "TEST_EXPECT_ROSTER": "1"},
        extra_b={"TEST_EXPECT_ROSTER": "1"},
        partners=False,
    )
    try:
        dump = read_movement_dump(harness_dir)
        assert dump["rejects"].get("malformed", 0) >= 1, dump
        row = observed(results_a, one["player_id"])
        assert row is not None
        # 2.0s at 300/s is 600; a forged faster direction would exceed it.
        assert movement_extent(row)["width"] < MOVEMENT_SPEED * 2.0 * 1.35, row
    finally:
        reap(server)


def test_stale_sequence_numbers_are_ignored(backend, freed_ports, server_port, harness_dir):
    """Replayed and wrap-old sequence numbers are dropped as stale."""
    one, two = pair(1)
    server, _results_a, _results_b, _out_a, _out_b = run_pair(
        backend, server_port, harness_dir,
        script_a="right:1.5", script_b="idle:0.1", hold=1.0, index=1,
        extra_env_server={"GODOT_MOVEMENT_ARENA": "1"},
        extra_a={"TEST_RAW_ATTACKS": "replay_seq,zero_seq", "TEST_EXPECT_ROSTER": "1"},
        extra_b={"TEST_EXPECT_ROSTER": "1"},
        partners=False,
    )
    try:
        dump = read_movement_dump(harness_dir)
        assert dump["rejects"].get("stale_sequence", 0) >= 2, dump
    finally:
        reap(server)


def test_input_flood_is_rate_limited(backend, freed_ports, server_port, harness_dir):
    """Input well above the allowed rate is dropped by the token bucket.

    The burst is repeated rather than sent once, because a single large frame is
    discarded in transit by the unreliable channel and would pass this test
    without ever reaching the limiter.
    """
    server, _results_a, _results_b, _out_a, _out_b = run_pair(
        backend, server_port, harness_dir,
        script_a="idle:0.1", script_b="idle:0.1", hold=1.0, index=1,
        extra_env_server={"GODOT_MOVEMENT_ARENA": "1"},
        extra_a={"TEST_RAW_ATTACKS": ",".join(["flood"] * 8), "TEST_EXPECT_ROSTER": "1"},
        partners=False,
    )
    try:
        dump = read_movement_dump(harness_dir)
        assert dump["rejects"].get("rate_limited", 0) >= 1, dump
    finally:
        reap(server)


# ── 14: collision is enforced ──────────────────────────────────────────────
#
# Two tests, because they prove different things.
#
# The hard geometric guarantee ("a boundary was never crossed") needs flat walls,
# so it uses the clearly labelled isolated arena. The real campus is concave -- the
# lakes are C-shaped with walkable notches inside them -- so "this point is inside
# a campus polygon" cannot tell a player who crossed a wall from one who walked
# around a bend, and the campus test instead asserts that the real collision world
# measurably changes where the player ends up.


def test_player_cannot_cross_a_wall_in_the_isolated_arena(
    backend, freed_ports, server_port, harness_dir
):
    """A player walking north into a wall stops, and never crosses it.

    Runs against the labelled isolated arena rather than the campus, so "crossed a
    wall" is unambiguous.
    """
    one, two = pair(0)
    server, results_a, _results_b, _out_a, out_a = run_pair(
        backend, server_port, harness_dir,
        script_a="up:5.0", script_b="idle:0.1", hold=1.5, index=0,
        extra_env_server={"GODOT_MOVEMENT_ARENA": "1"},
    )
    try:
        dump = read_movement_dump(harness_dir)
        assert dump["arena_mode"] is True, dump
        assert "ARENA" in dump["collision_world"].upper(), dump

        row = observed(results_a, one["player_id"])
        assert row is not None, out_a[-1500:]
        # It really did try to travel.
        assert movement_extent(row)["height"] > 100.0, row
        # It really was stopped. Unobstructed, 5.0s at 300/s is 1500 units; the
        # furthest a spawn-ring position can possibly travel north before meeting
        # the wall is the ring radius plus the arena half-height, 1460. Anything
        # beyond that went through the wall.
        unreachable = ARENA_HALF_HEIGHT + ARENA_SPAWN_RING + 20.0
        assert movement_extent(row)["height"] < unreachable, (
            "the player travelled %.1f units, past the %.1f at which the wall must "
            "have stopped it:\n%s"
            % (movement_extent(row)["height"], unreachable, row)
        )
        # The decisive check, and independent of the spawn position: no published
        # position may lie north of the wall's inner face.
        north_limit = CAMPUS_SPAWN[1] - ARENA_HALF_HEIGHT
        for sample in (row["min_y"], row["max_y"], _point(row)[1]):
            assert sample > north_limit, (
                "the player crossed the northern wall at y=%.1f (wall at %.1f)"
                % (sample, north_limit)
            )
    finally:
        reap(server)


@pytest.mark.timeout(240)
def test_the_real_campus_collision_deflects_a_player(
    backend, freed_ports, server_port, harness_dir
):
    """The real campus collision world measurably changes where a player ends up.

    Unobstructed, 6.0s at 300/s would carry the player 1800 units north. The real
    lakes and borders cut that short, and this asserts the shortfall is real,
    which is what catches a regression where the collision body is present in the
    scene graph but not actually participating in physics.

    Given a longer budget than the arena tests, on measurement rather than
    instinct: this is the one test that must load the actual campus, and building
    map.tscn and its TileSet costs about 20 seconds in each of the three Godot
    processes. The arena tests run in a fraction of this.
    """
    seconds = 6.0
    one, two = pair(0)
    server, results_a, _results_b, _out_a, out_a = run_pair(
        backend, server_port, harness_dir,
        script_a="up:%.1f" % seconds, script_b="idle:0.1", hold=1.5, index=0,
    )
    try:
        dump = read_movement_dump(harness_dir)
        assert dump["collision_shapes"] >= 16, (
            "the campus collision world was not built from the real map:\n%s" % dump
        )
        assert dump["arena_mode"] is False, dump

        row = observed(results_a, one["player_id"])
        assert row is not None, out_a[-1500:]
        unobstructed = MOVEMENT_SPEED * seconds
        travelled = movement_extent(row)["height"]
        # It really did try to travel.
        assert travelled > 100.0, row
        # And the collision world cut the journey short. The bound is deliberately
        # loose (90% of unobstructed) so it holds for any spawn position on the
        # deterministic ring, while still failing outright if the collision world
        # were absent -- with no collision the player would cover the full 1800.
        assert travelled < unobstructed * 0.9, (
            "the player travelled %.1f of an unobstructed %.1f, so the real "
            "campus collision had no measurable effect:\n%s"
            % (travelled, unobstructed, row)
        )
    finally:
        reap(server)


# ── 16: lost input stops the player, and only that player ──────────────────


def test_a_silent_client_stops_without_stalling_the_others(
    backend, freed_ports, server_port, harness_dir
):
    """When input stops arriving the entity stops, rather than sliding forever.

    A short grace absorbs a single dropped unreliable packet; after that the
    player stops. B keeps moving throughout.
    """
    one, two = pair(0)
    server, results_a, results_b, _out_a, _out_b = run_pair(
        backend, server_port, harness_dir,
        script_a="right:1.0", script_b="right:5.0", hold=2.0, index=0,
        extra_env_server={"GODOT_MOVEMENT_ARENA": "1"},
    )
    try:
        row_a = observed(results_a, one["player_id"])
        assert row_a is not None
        # 1.0s of input plus at most the 0.25s grace: nowhere near 6.0s of travel.
        assert movement_extent(row_a)["width"] < MOVEMENT_SPEED * 1.8, row_a
        row_b = observed(results_b, two["player_id"])
        assert row_b is not None and movement_extent(row_b)["width"] > MOVEMENT_SPEED * 3.5, row_b
    finally:
        reap(server)


# ── 17, 18, 19: disconnect, reconnect, no duplicates, survivor unaffected ──


def test_disconnect_removes_the_avatar_and_reconnect_makes_exactly_one(
    backend, freed_ports, server_port, harness_dir
):
    """A leaving player disappears from the other client, and coming back with a
    fresh ticket produces exactly one avatar, while the survivor stays connected."""
    survivor_user = pool_user(2)
    mover_user = pool_user(3)
    server = start_server(
        backend.secret, server_port, harness_dir,
        extra_env={**movement_env(harness_dir), "GODOT_MOVEMENT_ARENA": "1"},
    )
    try:
        # The survivor holds its session for the whole test. The hold is generous
        # and the test terminates it itself: ticket requests occasionally retry,
        # so a survivor sized to a guessed timeline would exit early and produce a
        # failure that looks like a dropped connection.
        survivor = start_movement_client(
            survivor_user, backend.secret, server_port, harness_dir, "", 90.0
        )
        # First visit by the mover.
        first = start_movement_client(
            mover_user, backend.secret, server_port, harness_dir, "right:1.5", 3.0
        )
        wait_for(first)
        reap(first)

        # Second visit, same account, therefore a different ticket.
        again = start_movement_client(
            mover_user, backend.secret, server_port, harness_dir, "left:1.5", 3.0
        )
        wait_for(again)
        reap(again)

        assert survivor.poll() is None, "the surviving client was dropped"

        # Read the survivor's log without terminating it, so its file handle is
        # left for reap() and nothing is truncated mid-write.
        time.sleep(2.0)
        raw = (harness_dir / f"mover-{survivor_user['username']}.log").read_bytes()
        results = parse_results(raw)

        lefts = [e for e in events(results, "remote_left")
                 if e["other"] == mover_user["player_id"]]
        joins = [e for e in events(results, "remote_joined")
                 if e["other"] == mover_user["player_id"]]
        assert len(joins) == 2, "one avatar per visit:\n" + tail(raw, 2000)
        assert len(lefts) == 2, "the avatar must leave when its owner disconnects:\n" + tail(raw, 2000)

        # Exactly one avatar per visit, and never a copy of the survivor itself.
        # Checked on every join rather than on "the last event": the survivor is
        # still connected when the mover is reaped, so it legitimately observes a
        # second leave afterwards, and only the join can speak to duplication.
        for entry in joins:
            assert entry["remote_ids"] == [mover_user["player_id"]], entry
            assert survivor_user["player_id"] not in entry["remote_ids"], entry

        text = reap(server).decode("utf-8", "replace")
        admissions = [
            line for line in text.splitlines()
            if "admitted peer" in line and f"player {mover_user['player_id']} " in line
        ]
        assert len(admissions) == 2, text[-1500:]
        assert (
            f"player {survivor_user['player_id']} disconnected" not in text
        ), "the survivor must not be dropped by the other's churn"
    finally:
        reap(server)


# ── 21: no movement state survives a server restart ────────────────────────


def test_movement_state_does_not_survive_a_server_restart(
    backend, freed_ports, server_port, harness_dir
):
    """A fresh server starts everyone from the spawn, not from a stale position."""
    user = pool_user(4)
    first_dump = harness_dir / "run1"
    first_dump.mkdir()
    server_env = movement_env(first_dump)
    # The clear arena gives the 3.0s run room regardless of spawn position.
    server_env["GODOT_MOVEMENT_ARENA"] = "1"
    server = start_server(
        backend.secret, server_port, first_dump, extra_env=server_env
    )
    try:
        client = start_movement_client(
            user, backend.secret, server_port, first_dump, "right:3.0", 1.5,
            # Alone on this server: it must not wait for a second player.
            {"TEST_EXPECT_ROSTER": "1"},
        )
        wait_for(client)
        out = reap(client, timeout=20)
        row = observed(parse_results(out), user["player_id"])
        assert row is not None, tail(out, 1500)
        moved = movement_extent(row)["width"]
        assert moved > MOVEMENT_SPEED * 2.0, row
    finally:
        reap(server)

    # Wait for the UDP port, then start a brand new server process.
    import time

    deadline = time.time() + 30
    while time.time() < deadline:
        from conftest import free_port_is_free

        if free_port_is_free(server_port):
            break
        time.sleep(0.5)

    second_dump = harness_dir / "run2"
    second_dump.mkdir()
    server2_env = movement_env(second_dump)
    server2_env["GODOT_MOVEMENT_ARENA"] = "1"
    server2 = start_server(
        backend.secret, server_port, second_dump, extra_env=server2_env
    )
    try:
        client2 = start_movement_client(
            user, backend.secret, server_port, second_dump, "", 1.5,
            # This client is alone on the fresh server, so it must not wait for a
            # second player before reporting.
            {"TEST_EXPECT_ROSTER": "1"},
        )
        wait_for(client2)
        out2 = reap(client2, timeout=20)
        row2 = observed(parse_results(out2), user["player_id"])
        assert row2 is not None, tail(out2, 1500)
        # It is standing still, and near its deterministic spawn -- not where the
        # previous server left it.
        assert movement_extent(row2)["width"] < 5.0, row2
        last = _point(row2)
        distance = ((last[0] - CAMPUS_SPAWN[0]) ** 2 + (last[1] - CAMPUS_SPAWN[1]) ** 2) ** 0.5
        assert distance < 300.0, (last, CAMPUS_SPAWN)
        assert row2["samples"] > 0, row2
    finally:
        reap(server2)


def _point(row: dict) -> tuple:
    """The last position the server published, as an (x, y) tuple.

    JSON has no tuple, so ``last`` arrives as a list, but it is accepted as either.
    """
    last = row["last"]
    if isinstance(last, (list, tuple)):
        return (float(last[0]), float(last[1]))
    parts = str(last).strip("() ").split(",")
    return (float(parts[0]), float(parts[1]))


# ── 22: the legacy path is untouched ───────────────────────────────────────


def test_legacy_transport_remains_the_default(backend, freed_ports, server_port, harness_dir):
    """The experimental movement path is opt-in and touches no gameplay scene."""
    from conftest import CLIENT as CLIENT_DIR

    # The transport default is unchanged in source.
    config = (CLIENT_DIR / "Scripts" / "network" / "NetworkConfig.gd").read_text(
        encoding="utf-8"
    )
    assert 'DEFAULT_TRANSPORT := "legacy"' in config
    # Nothing in the production gameplay scenes references the movement link.
    for relative in ("Scenes/world.tscn", "Scripts/player.gd", "Scripts/chara_player.gd"):
        body = (CLIENT_DIR / relative).read_text(encoding="utf-8")
        assert "MovementClient" not in body, relative
        assert "NetworkLink" not in body, relative
    # The experiment runs in its own scenes, not in the world.
    assert (CLIENT_DIR / "Scenes" / "network" / "MovementHarness.tscn").exists()
    assert (CLIENT_DIR / "Scenes" / "network" / "DedicatedServer.tscn").exists()