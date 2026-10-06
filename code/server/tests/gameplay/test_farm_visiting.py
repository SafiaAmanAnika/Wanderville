"""One persistent world per player, and invitation-only read-only visits."""

from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta

from sqlalchemy import select, update

from app.core.exceptions import AppError
from app.core.clock import utcnow
from app.core.rate_limit import limiter
from app.modules.realtime.models import Presence
from app.modules.realtime.service import PRESENCE_TTL_SECONDS, RealtimeService
from app.modules.social.farm_visiting import FarmVisitService
from app.modules.social.models import FarmInvitation, FarmVisitSession
from app.modules.world.access import resolve
from app.modules.world.models import PlayerWorld
from app.modules.world.worker import tick


def ok(response):
    assert response.status_code == 200, response.text
    return response.json()["data"]


def accounts(factory, count, prefix="guest"):
    """Create ``count`` players.

    The auth endpoints are rate limited per IP, and these tests deliberately build
    a full house of five visitors, so the process-local limiter is reset between
    signups rather than weakening the production limit for the whole suite.
    """
    made = []
    for index in range(count):
        limiter.clear()
        made.append(factory(f"{prefix}_{index}"))
    limiter.clear()
    return made


def befriend(client, a, b):
    ok(client.post("/social/requests", headers=a.headers, json={"target_id": b.id}))
    ok(
        client.post(
            f"/social/friends/{a.id}", headers=b.headers, json={"action": "accept"}
        )
    )


def invite(client, host, guest):
    """Host invites ``guest`` and the guest accepts. Returns the session payload."""
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


def world_of(db, player_id):
    return db.query(PlayerWorld).filter(PlayerWorld.owner_id == player_id).one()


def active_visits(db):
    return list(
        db.scalars(
            select(FarmVisitSession).where(FarmVisitSession.status == "ACTIVE")
        )
    )


def occupancy(client, host):
    """The host's own view of how many visitors are standing in their farm."""
    return ok(client.get("/farm/visiting/visitors", headers=host.headers))["visitor_count"]


def test_owner_has_exactly_one_world(client, account, db):
    host, guest = account(), account("stranger")
    befriend(client, host, guest)
    first = ok(client.get("/world/me", headers=host.headers))
    assert ok(client.get("/world/me", headers=host.headers))["id"] == first["id"]
    assert first["owner_id"] == host.id
    assert world_of(db, host.id).id == first["id"]
    # Request fields can never assert ownership of someone else's world.
    response = client.post(
        "/realtime/enter",
        headers=host.headers,
        json={"owner_id": guest.id, "player_id": guest.id},
    )
    assert response.status_code == 403, response.text
    assert ok(client.get("/world/me", headers=host.headers))["id"] == first["id"]


def test_friendship_alone_is_not_entry(client, account, db):
    host, guest = account(), account("friend_not_guest")
    befriend(client, host, guest)
    denied = client.post(
        "/realtime/enter", headers=guest.headers, json={"owner_id": host.id}
    )
    assert denied.status_code == 403
    assert denied.json()["error"] == "FORBIDDEN"
    assert ok(client.get("/farm/visiting/session", headers=guest.headers))[
        "session_mode"
    ] == "OWNER"
    invite(client, host, guest)
    ok(client.post("/realtime/enter", headers=guest.headers, json={"owner_id": host.id}))
    assert ok(client.get("/farm/visiting/session", headers=guest.headers))[
        "session_mode"
    ] == "VISITOR"


def test_capacity_is_five_and_frees_on_leave(client, account, db):
    host = account()
    guests = accounts(account, 6)
    for guest in guests:
        befriend(client, host, guest)
    assert world_of(db, host.id).visitor_limit == 5
    for guest in guests[:5]:
        invite(client, host, guest)
    assert len(active_visits(db)) == 5
    assert occupancy(client, host) == 5

    # The sixth guest has a valid invitation but no slot to accept into.
    offer = ok(
        client.post(
            "/farm/visiting/invitations",
            headers=host.headers,
            json={"target_id": guests[5].id},
        )
    )
    full = client.post(
        f"/farm/visiting/invitations/{offer['id']}/accept", headers=guests[5].headers
    )
    assert full.status_code == 409, full.text
    # The refusal is idempotent: no session row was created.
    assert db.get(FarmInvitation, offer["id"]).status == "PENDING"
    assert len(active_visits(db)) == 5

    ok(client.post("/farm/visiting/leave", headers=guests[0].headers))
    assert len(active_visits(db)) == 4
    ok(
        client.post(
            f"/farm/visiting/invitations/{offer['id']}/accept", headers=guests[5].headers
        )
    )
    assert len(active_visits(db)) == 5


def test_capacity_is_atomic_under_a_real_race(client, account, session_factory, db):
    """Two guests accepting the last slot concurrently: exactly one may win."""
    host = account()
    seated = accounts(account, 4, "seated")
    racers = accounts(account, 2, "racer")
    for guest in seated + racers:
        befriend(client, host, guest)
    for guest in seated:
        invite(client, host, guest)
    assert len(active_visits(db)) == 4

    offers = {}
    for guest in racers:
        offers[guest.id] = ok(
            client.post(
                "/farm/visiting/invitations",
                headers=host.headers,
                json={"target_id": guest.id},
            )
        )["id"]

    def accept(guest_id):
        # A separate session per racer: the real deployment contends on the
        # database, not inside one unit of work.
        session = session_factory()
        try:
            FarmVisitService(session).accept(guest_id, offers[guest_id])
            return "accepted"
        except AppError:
            return "rejected"
        finally:
            session.close()

    with ThreadPoolExecutor(max_workers=2) as pool:
        outcomes = list(pool.map(accept, [racers[0].id, racers[1].id]))

    assert outcomes.count("accepted") == 1, outcomes
    db.expire_all()
    assert len(active_visits(db)) == 5


def test_visitor_reads_host_world_and_cannot_mutate_it(client, account, db):
    host, guest = account(), account("reader")
    befriend(client, host, guest)
    ok(
        client.post(
            "/inventory/add", headers=host.headers,
            json={"item_code": "wheat_seed", "quantity": 5},
        )
    )
    ok(client.post("/farm/till", headers=host.headers, json={"x": 1, "y": 1}))
    planted = ok(
        client.post(
            "/farm/plant", headers=host.headers, json={"x": 1, "y": 1, "item_code": "wheat_seed"}
        )
    )
    invite(client, host, guest)

    session = ok(client.get("/farm/visiting/session", headers=guest.headers))
    assert session["session_mode"] == "VISITOR"
    assert session["host_player_id"] == host.id
    assert session["current_world_id"] != session["owned_world_id"]
    assert session["current_world_id"] == world_of(db, host.id).id

    # The visitor sees the host's tiles, not their own empty farm.
    seen = ok(client.get("/farm/visiting/state", headers=guest.headers))
    assert [plot["id"] for plot in seen["plots"]] == [planted["plot"]["id"]]

    refused = [
        ("POST", "/farm/till", {"x": 2, "y": 2}),
        ("POST", "/farm/water", {"plot_id": planted["plot"]["id"]}),
        ("POST", "/farm/plant", {"x": 3, "y": 3, "item_code": "wheat_seed"}),
        ("POST", "/farm/harvest", {"plot_id": planted["plot"]["id"]}),
        ("POST", "/farm/relocate", {"plot_id": planted["plot"]["id"], "x": 4, "y": 4}),
        ("POST", "/farm/refill", {}),
        ("PUT", "/world/tile", {"x": 5, "y": 5, "kind": "soil"}),
        ("PUT", "/world/tiles", {"tiles": {}}),
    ]
    for method, path, payload in refused:
        response = client.request(method, path, headers=guest.headers, json=payload)
        assert response.status_code in (403, 409, 410), (path, response.text)

    # Nothing the visitor attempted changed the host's farm.
    after = ok(client.get("/farm/plots", headers=host.headers))
    assert [plot["id"] for plot in after["plots"]] == [planted["plot"]["id"]]
    assert after["plots"][0]["item_code"] == "wheat"


def test_guest_can_hold_only_one_visit_at_a_time(client, account, db):
    first_host, second_host, guest = account(), account("other_host"), account("traveller")
    befriend(client, first_host, guest)
    befriend(client, second_host, guest)
    invite(client, first_host, guest)
    ok(client.post("/realtime/enter", headers=guest.headers, json={"owner_id": first_host.id}))
    blocked = client.post(
        "/realtime/enter", headers=guest.headers, json={"owner_id": second_host.id}
    )
    assert blocked.status_code == 403
    # Ownership never changes because of where you are standing.
    session = ok(client.get("/farm/visiting/session", headers=guest.headers))
    assert session["host_player_id"] == first_host.id
    # The guest still owns their own world; visiting never transfers ownership.
    assert session["owned_world_id"] == world_of(db, guest.id).id
    assert session["owned_world_id"] != session["current_world_id"]


def test_leave_returns_the_visitor_home_and_is_idempotent(client, account):
    host, guest = account(), account("leaver")
    befriend(client, host, guest)
    invite(client, host, guest)
    ok(client.post("/realtime/enter", headers=guest.headers, json={"owner_id": host.id}))
    left = ok(client.post("/farm/visiting/leave", headers=guest.headers))
    assert left["reason"] == "LEFT"
    assert left["session_mode"] == "OWNER"
    assert left["current_world_id"] == left["owned_world_id"]
    assert left["host_player_id"] == host.id
    again = ok(client.post("/farm/visiting/leave", headers=guest.headers))
    assert again["reason"] == "NOT_VISITING"
    assert again["current_world_id"] == again["owned_world_id"]


def test_host_kick_and_host_disconnect_reclaim_the_slot(client, account, db):
    host, guest = account(), account("kicked")
    befriend(client, host, guest)
    invite(client, host, guest)
    visit = active_visits(db)[0]
    ok(client.delete(f"/farm/visiting/visitors/{visit.id}", headers=host.headers))
    db.expire_all()
    assert db.get(FarmVisitSession, visit.id).status == "KICKED"
    assert client.delete(
        f"/farm/visiting/visitors/{visit.id}", headers=host.headers
    ).status_code == 409

    invite(client, host, guest)
    assert len(active_visits(db)) == 1
    # Host going offline releases the visitor, exactly like the socket close path.
    RealtimeService(db).leave(host.id)
    assert active_visits(db) == []


def test_orphaned_visits_are_swept_when_the_host_never_closes(client, account, db):
    """A dead host leaves the visitor heartbeating; the sweep must still end it."""
    host, guest = account(), account("abandoned")
    befriend(client, host, guest)
    invite(client, host, guest)
    RealtimeService(db).enter(host.id, host.id)
    RealtimeService(db).enter(guest.id, host.id)
    assert len(active_visits(db)) == 1
    # The host vanishes with no close frame: no presence row, no leave call.
    db.execute(
        update(Presence)
        .where(Presence.player_id == host.id)
        .values(updated_at=utcnow() - timedelta(seconds=PRESENCE_TTL_SECONDS + 5))
    )
    db.commit()
    tick(db)
    assert active_visits(db) == []


def test_invitation_is_single_use_and_host_owned(client, account, db):
    host, guest = account(), account("once")
    befriend(client, host, guest)
    offer = ok(
        client.post(
            "/farm/visiting/invitations",
            headers=host.headers,
            json={"target_id": guest.id},
        )
    )
    # Re-inviting inside the window reuses the pending offer rather than spamming.
    same = ok(
        client.post(
            "/farm/visiting/invitations",
            headers=host.headers,
            json={"target_id": guest.id},
        )
    )
    assert same["id"] == offer["id"]
    ok(
        client.post(
            f"/farm/visiting/invitations/{offer['id']}/accept", headers=guest.headers
        )
    )
    assert db.get(FarmInvitation, offer["id"]).status == "ACCEPTED"
    assert client.post(
        f"/farm/visiting/invitations/{offer['id']}/accept", headers=guest.headers
    ).status_code == 409
    ok(client.post("/farm/visiting/leave", headers=guest.headers))

    # Only the host may cancel, and a resolved offer frees the key for a re-invite.
    assert client.delete(
        f"/farm/visiting/invitations/{offer['id']}", headers=guest.headers
    ).status_code in (403, 404)
    fresh = ok(
        client.post(
            "/farm/visiting/invitations",
            headers=host.headers,
            json={"target_id": guest.id},
        )
    )
    assert fresh["id"] != offer["id"]
    ok(client.delete(f"/farm/visiting/invitations/{fresh['id']}", headers=host.headers))
    db.expire_all()
    assert db.get(FarmInvitation, fresh["id"]).status == "CANCELLED"
    # A cancelled offer is already resolved, so it cannot also be declined.
    assert client.post(
        f"/farm/visiting/invitations/{fresh['id']}/decline", headers=guest.headers
    ).status_code == 409


def test_visitor_enters_at_the_host_gate_not_their_own(client, account, db):
    host, guest = account(), account("traveller")
    befriend(client, host, guest)
    world = world_of(db, host.id)
    world.farm_entrance_x, world.farm_entrance_y = 1234.0, -567.0
    db.commit()
    invite(client, host, guest)
    presence = ok(client.post("/realtime/enter", headers=guest.headers,
                              json={"owner_id": host.id}))
    assert (presence["x"], presence["y"]) == (1234.0, -567.0)


def test_resolve_is_owner_without_a_visit(client, account, db):
    user = account()
    session = resolve(db, user.id)
    assert session.is_owner and not session.is_visitor
    assert session.current_world_id == session.owned_world_id
    assert session.public()["host_player_id"] is None
    assert session.public()["visit_session_id"] is None


def test_inbox_names_both_sides_of_an_invitation(client, account):
    """The guest's inbox is unusable without a host name on it.

    An invitation row carries only ids, so the client cannot show who is asking
    without the server resolving both players. The guest must see the host, the
    host must see the guest, and neither inbox may contain somebody else's
    offers.
    """
    host, guest, stranger = accounts(account, 3, prefix="inbox")
    befriend(client, host, guest)
    offer = ok(
        client.post(
            "/farm/visiting/invitations",
            headers=host.headers,
            json={"target_id": guest.id},
        )
    )
    inbox = ok(client.get("/farm/visiting/invitations", headers=guest.headers))
    assert len(inbox) == 1
    assert inbox[0]["id"] == offer["id"]
    assert inbox[0]["host_username"] == host.payload["username"]
    assert inbox[0]["guest_username"] == guest.payload["username"]

    outgoing = ok(
        client.get(
            "/farm/visiting/invitations?as_host=true", headers=host.headers
        )
    )
    assert [row["id"] for row in outgoing] == [offer["id"]]
    assert outgoing[0]["guest_username"] == guest.payload["username"]

    assert ok(client.get("/farm/visiting/invitations", headers=stranger.headers)) == []