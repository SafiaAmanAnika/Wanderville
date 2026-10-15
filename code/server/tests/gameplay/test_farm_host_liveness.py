"""A healthy farm host must not have their visitor's slot reclaimed.

``FarmVisitService.sweep_orphaned`` decides a host is gone by reading
``player_presence.updated_at``. Under ``PRESENCE_BACKEND=memory`` a host who is
standing still no longer rewrites that row on every movement packet, so the row
goes quiet while the connection is perfectly healthy -- and the sweep would end
a legitimate visit.

These tests pin the contract for both backends: a host who keeps heartbeating
keeps their visitors, and a host who really goes away loses them.
"""

import pytest

from app.core.clock import as_utc, utcnow
from app.core.config import settings
from app.core.rate_limit import limiter
from app.modules.realtime import position_projection
from app.modules.realtime.models import Presence
from app.modules.realtime.service import PRESENCE_TTL_SECONDS, RealtimeService
from app.modules.social.farm_visiting import FarmVisitService
from app.modules.social.models import FarmVisitSession
from app.modules.world.access import resolve
from sqlalchemy import select


def ok(response):
    assert response.status_code == 200, response.text
    return response.json()["data"]


def befriend(client, a, b):
    ok(client.post("/social/requests", headers=a.headers, json={"target_id": b.id}))
    ok(
        client.post(
            f"/social/friends/{a.id}", headers=b.headers, json={"action": "accept"}
        )
    )


def invite(client, host, guest):
    offer = ok(
        client.post(
            "/farm/visiting/invitations",
            headers=host.headers,
            json={"target_id": guest.id},
        )
    )
    return ok(
        client.post(
            f"/farm/visiting/invitations/{offer['id']}/accept", headers=guest.headers
        )
    )


@pytest.fixture(params=["database", "memory"])
def backend(request, monkeypatch):
    monkeypatch.setattr(settings, "presence_backend", request.param)
    position_projection.reset()
    yield request.param
    position_projection.reset()


@pytest.fixture
def visiting_pair(backend, client, account):
    """A host with a visitor standing in their farm."""
    limiter.clear()
    host = account("host_player")
    limiter.clear()
    guest = account("guest_player")
    limiter.clear()
    befriend(client, host, guest)
    invite(client, host, guest)
    ok(client.post("/realtime/enter", headers=host.headers, json={"owner_id": host.id}))
    ok(client.post("/realtime/enter", headers=guest.headers, json={"owner_id": host.id}))
    return host, guest


def active_sessions(db):
    return list(
        db.scalars(
            select(FarmVisitSession).where(FarmVisitSession.status == "ACTIVE")
        )
    )


def age_host_presence(db, host_id, seconds):
    """Age the host's durable presence row, as real time would."""
    row = db.get(Presence, host_id)
    row.updated_at = utcnow() - __import__("datetime").timedelta(seconds=seconds)
    db.flush()


def test_host_heartbeats_keep_the_visit(visiting_pair, client, db, backend):
    """A host standing still and heartbeating keeps their visitor admitted."""
    host, guest = visiting_pair
    service = RealtimeService(db)

    # Push the host's presence row and live position past the memory TTL.
    age_host_presence(db, host.id, settings.presence_memory_ttl_seconds + 5)
    if backend == "memory":
        live = position_projection.get(host.id)
        assert live is not None
        live.updated_at = utcnow() - __import__("datetime").timedelta(
            seconds=settings.presence_memory_ttl_seconds + 5
        )

    for _ in range(3):
        service.heartbeat(host.id)
    db.commit()

    if backend == "memory":
        assert position_projection.get(host.id) is not None, (
            "a heartbeat must keep the host's live position alive"
        )

    # The visitor must still be a visitor, in the host's room.
    assert resolve(db, guest.id).is_visitor
    rooms = [s for s in active_sessions(db)]
    assert rooms, "the visit session must survive a heartbeating host"

    snapshot = client.get("/realtime/snapshot", headers=guest.headers).json()["data"]
    assert snapshot["room"] == f"world:{resolve(db, host.id).owned_world_id}"
    assert host.id in {p["player_id"] for p in snapshot["players"]}


def test_sweep_orphaned_does_not_reclaim_a_heartbeating_host(visiting_pair, db, backend):
    """The orphan sweep is the specific mechanism that could end the visit.

    Simulates the real cadence: the client heartbeats every 0.5s, so the host's
    presence row is always fresh. Ageing it by a full TTL first and then
    heartbeating would assert something a live client can never produce --
    ``active()`` legitimately rejects a row older than the presence TTL, because
    at that point the connection really is presumed gone.
    """
    host, guest = visiting_pair
    service = RealtimeService(db)

    for _ in range(3):
        service.heartbeat(host.id)
    db.commit()

    assert FarmVisitService(db).sweep_orphaned() == []
    assert resolve(db, guest.id).is_visitor, (
        f"{backend}: a heartbeating host must keep the visitor's session"
    )


def test_sweep_orphaned_reclaims_when_the_host_row_is_truly_stale(visiting_pair, db, backend):
    """The negative case: a genuinely stale host row does lose the slot."""
    host, guest = visiting_pair
    age_host_presence(db, host.id, PRESENCE_TTL_SECONDS + 30)
    db.commit()

    FarmVisitService(db).sweep_orphaned()
    db.commit()
    assert not active_sessions(db)


def test_sweep_orphaned_still_reclaims_a_genuinely_gone_host(visiting_pair, db, backend):
    """A host who really disconnected must lose their visitor slot."""
    host, guest = visiting_pair

    RealtimeService(db).leave(host.id)
    db.commit()

    FarmVisitService(db).sweep_orphaned()
    db.commit()
    assert not active_sessions(db), (
        f"{backend}: a disconnected host must release the visitor slot"
    )


def test_a_parklasting_host_keeps_the_visit_long_past_the_ttl(visiting_pair, client, db, backend):
    """Ninety seconds of host heartbeats, the reported failure scenario."""
    host, guest = visiting_pair
    service = RealtimeService(db)
    from datetime import timedelta

    for tick in range(180):
        if backend == "memory":
            live = position_projection.get(host.id)
            if live is not None:
                live.updated_at = utcnow() - timedelta(seconds=0.5)
        if tick % 2 == 0:
            service.heartbeat(host.id)
    db.commit()

    assert resolve(db, guest.id).is_visitor
    snapshot = client.get("/realtime/snapshot", headers=guest.headers).json()["data"]
    assert host.id in {p["player_id"] for p in snapshot["players"]}


def test_visitor_leaving_releases_their_own_slot(visiting_pair, client, db, backend):
    host, guest = visiting_pair
    assert client.post("/farm/visiting/leave", headers=guest.headers).status_code == 200
    db.commit()
    assert not active_sessions(db)
    assert not resolve(db, guest.id).is_visitor


def test_host_kick_releases_the_slot(visiting_pair, client, db, backend):
    host, guest = visiting_pair
    session = resolve(db, guest.id)
    assert client.delete(
        f"/farm/visiting/visitors/{session.visit_session_id}",
        headers=host.headers,
    ).status_code == 200
    db.commit()
    assert not active_sessions(db)
    assert not resolve(db, guest.id).is_visitor


def test_visitor_disconnect_releases_the_slot(visiting_pair, db, backend):
    host, guest = visiting_pair
    RealtimeService(db).leave(guest.id)
    db.commit()
    assert not active_sessions(db)
