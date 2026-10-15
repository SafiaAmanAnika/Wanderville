"""The client's enter payload carries a world id where the server reads a player id.

The real Godot call chain is:

    GameState.desired_world_id()  -> current_world_id   (a WORLD id)
    RealtimeClient.enter_world()  -> {"owner_id": ...} (sent verbatim)
    RealtimeService.room_for()    -> compares against session.host_player_id

A world is provisioned 1:1 at signup, so on an untouched database
``player.id == world.id`` and the mix-up is invisible. That is why the existing
suite, which always sends ``owner_id=host.id``, never exercises the case.

The two sequences stop agreeing as soon as an account is deleted, and that has
already happened in the local development database: ``player_id=2`` owns
``world_id=2`` because the row for player 1 no longer exists. Once they differ,
a visitor whose client sends the world id is refused the farm they are standing
in.

``room_for`` is tested directly with a hand-built session so the divergence is
exact and deterministic rather than dependent on sequence state. The HTTP tests
then cover the authorization invariants that must survive the fix.
"""

from dataclasses import replace

import pytest

from app.core.exceptions import Forbidden
from app.modules.realtime.service import CAMPUS_ROOM, RealtimeService, world_room
from app.modules.world.access import MODE_OWNER, MODE_VISITOR, WorldSession

VISITOR_PLAYER = 7
HOST_PLAYER = 3
HOST_WORLD = 42  # deliberately unrelated to HOST_PLAYER
OWN_WORLD = 91


def visitor_session():
    return WorldSession(
        player_id=VISITOR_PLAYER,
        owned_world_id=OWN_WORLD,
        current_world_id=HOST_WORLD,
        session_mode=MODE_VISITOR,
        host_player_id=HOST_PLAYER,
        visit_session_id=5,
    )


def owner_session():
    return WorldSession(
        player_id=HOST_PLAYER,
        owned_world_id=OWN_WORLD,
        current_world_id=OWN_WORLD,
        session_mode=MODE_OWNER,
        host_player_id=None,
        visit_session_id=None,
    )


# ── the defect ────────────────────────────────────────────────────────────


def test_visitor_sending_the_world_id_is_now_admitted():
    """Regression guard for the fixed defect.

    Before this change ``room_for`` compared the client's ``owner_id`` only with
    ``session.host_player_id``, so a visitor whose client sent the world id was
    refused with "Leave your current farm before visiting another farm" -- for
    the farm they were already standing in.
    """
    assert RealtimeService.room_for(None, visitor_session(), owner_id=HOST_WORLD) == (
        world_room(HOST_WORLD)
    )


def test_the_two_identifiers_really_do_differ():
    assert HOST_WORLD != HOST_PLAYER
    assert visitor_session().current_world_id == HOST_WORLD
    assert visitor_session().host_player_id == HOST_PLAYER


# ── required behaviour after the fix ───────────────────────────────────────


def test_visitor_may_name_their_visit_by_world_id():
    session = visitor_session()
    assert RealtimeService.room_for(None, session, owner_id=HOST_WORLD) == world_room(
        HOST_WORLD
    )


def test_visitor_may_still_name_their_visit_by_host_player_id():
    """The historical owner_id=<host player id> payload stays valid."""
    session = visitor_session()
    assert RealtimeService.room_for(
        None, session, owner_id=HOST_PLAYER
    ) == world_room(HOST_WORLD)


def test_visitor_may_omit_the_identifier():
    session = visitor_session()
    assert RealtimeService.room_for(None, session) == world_room(HOST_WORLD)
    assert RealtimeService.room_for(None, session, owner_id=None) == world_room(
        HOST_WORLD
    )


def test_visitor_may_not_name_a_foreign_world_by_id():
    """Accepting a world id must not let a visitor hop to another farm."""
    session = visitor_session()
    with pytest.raises(Forbidden):
        RealtimeService.room_for(None, session, owner_id=9999)


def test_visitor_may_not_name_a_foreign_host_by_player_id():
    session = visitor_session()
    with pytest.raises(Forbidden):
        RealtimeService.room_for(None, session, owner_id=1234)


def test_owner_may_enter_their_own_farm_by_world_id():
    session = owner_session()
    assert RealtimeService.room_for(None, session, owner_id=OWN_WORLD) == world_room(
        OWN_WORLD
    )


def test_owner_may_enter_their_own_farm_by_player_id():
    session = owner_session()
    assert RealtimeService.room_for(None, session, owner_id=HOST_PLAYER) == world_room(
        OWN_WORLD
    )


def test_owner_defaults_to_the_campus():
    session = owner_session()
    assert RealtimeService.room_for(None, session) == CAMPUS_ROOM


def test_friendship_alone_is_not_entry():
    """Naming a world that is not yours is refused whether or not it exists."""
    session = owner_session()
    with pytest.raises(Forbidden, match="Accept a farm invitation"):
        RealtimeService.room_for(None, session, owner_id=HOST_WORLD)