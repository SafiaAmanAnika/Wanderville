from datetime import timedelta

import pytest
from jose import jwt
from sqlalchemy import event, func, select
from starlette.websockets import WebSocketDisconnect

from app.core.clock import as_utc, utcnow
from app.core.config import settings
from app.core.progression import LEVEL_AURA_REWARDS
from app.modules.economy.service import EconomyService
from app.modules.fishing.models import GroundDrop
from app.modules.inventory.models import ItemDefinition
from app.modules.inventory.service import InventoryService
from app.modules.notifications.models import Notification
from app.modules.pets.models import PlayerPet
from app.modules.realtime.models import Presence
from app.modules.realtime.protocol import RealtimeProtocol
from app.modules.realtime.service import RealtimeService
from app.modules.shop.models import ItemRule
from app.modules.social.models import FarmInvitation as Invite
from app.modules.world.worker import tick


def ok(response):
    assert response.status_code == 200, response.text
    return response.json()["data"]


def add(client, user, code, quantity=1):
    ok(client.post("/inventory/add", headers=user.headers,
                   json={"item_code": code, "quantity": quantity}))


def friends(client, a, b):
    ok(client.post("/social/requests", headers=a.headers, json={"target_id": b.id}))
    ok(client.post(f"/social/friends/{a.id}", headers=b.headers, json={"action": "accept"}))


@pytest.mark.parametrize("authenticated", [False, True])
@pytest.mark.parametrize("packet,code", [
    ("{", 1008), ("[]", 1008), ("x" * 8193, 1009),
    ('{"type":"snapshot","data":"' + chr(30028) * 2800 + '"}', 1009),
    (b"binary", 1003),
])
def test_socket_rejects_bad_frames(client, account, authenticated, packet, code):
    user = account()
    with client.websocket_connect("/realtime/ws") as ws:
        if authenticated:
            ws.send_json({"type": "auth", "token": user.tokens["access_token"]})
            assert ws.receive_json()["type"] == "snapshot"
        if isinstance(packet, bytes):
            ws.send_bytes(packet)
        else:
            ws.send_text(packet)
        with pytest.raises(WebSocketDisconnect) as error:
            ws.receive_json()
        assert error.value.code == code


def test_socket_url_token_and_expired_revoked_tokens(client, account):
    user = account()
    with client.websocket_connect("/realtime/ws?token=invalid") as ws:
        ws.send_json({"type": "snapshot"})
        with pytest.raises(WebSocketDisconnect) as error:
            ws.receive_json()
        assert error.value.code == 1008
    claims = jwt.get_unverified_claims(user.tokens["access_token"])
    claims["exp"] = int((utcnow() - timedelta(seconds=1)).timestamp())
    expired = jwt.encode(claims, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)
    with client.websocket_connect("/realtime/ws") as ws:
        ws.send_json({"type": "auth", "token": expired})
        assert ws.receive_json()["status"] == 401
    with client.websocket_connect("/realtime/ws") as ws:
        ws.send_json({"type": "auth", "token": user.tokens["access_token"]})
        assert ws.receive_json()["type"] == "snapshot"
        ok(client.put("/auth/change-password", headers=user.headers,
                      json={"current_password": user.payload["password"],
                            "new_password": "Changed-Pass456!"}))
        ws.send_json({"type": "snapshot"})
        # Idle snapshots sent before revocation may already be queued.
        for _ in range(10):
            reply = ws.receive_json()
            if reply.get("status") == 401:
                break
        assert reply.get("status") == 401


def test_snapshots_release_connection_and_batch_names(client, account, db):
    a, b = account(), account("nearby_user")
    for user in (a, b):
        ok(client.post("/realtime/enter", headers=user.headers, json={"location": "social_lobby"}))
    statements = []
    def capture(conn, cursor, statement, parameters, context, executemany):
        statements.append(statement)
    event.listen(db.bind, "before_cursor_execute", capture)
    try:
        reply = RealtimeProtocol(db).step(a.tokens["access_token"], {"type": "snapshot"})
        assert reply["type"] == "snapshot"
        assert len(reply["data"]["players"]) == 2
        assert not db.in_transaction()
        # Includes the owned-world lookup needed for private-room metadata.
        assert len(statements) <= 9
    finally:
        event.remove(db.bind, "before_cursor_execute", capture)


def test_reconnect_emote_and_private_room_expiry(client, account, db):
    a, b = account(), account("room_owner")
    service = RealtimeService(db)
    first = service.enter(a.id)
    assert service.enter(a.id)["sequence"] == first["sequence"]
    row = db.get(Presence, a.id)
    row.x, row.emote, row.emote_until = 1950, "wave", utcnow() - timedelta(seconds=1)
    db.commit()
    assert service.snapshot(a.id)["players"][0]["emote"] is None
    assert service.enter(a.id)["x"] == 1950
    row.updated_at = utcnow() - timedelta(seconds=61)
    db.commit()
    assert service.enter(a.id)["x"] == 1950  # Reconnect restores persisted position.
    assert client.post("/realtime/enter", headers=a.headers,
json={"owner_id": b.id}).status_code == 403
    friends(client, a, b)
    # Friendship alone is not entry: only an accepted invitation admits a visitor.
    assert client.post("/realtime/enter", headers=a.headers,
                       json={"owner_id": b.id}).status_code == 403
    invite = ok(client.post("/social/invites", headers=b.headers, json={"target_id": a.id}))
    ok(client.post(f"/social/invites/{invite['id']}/accept", headers=a.headers))
    ok(client.post("/realtime/enter", headers=a.headers, json={"owner_id": b.id}))
    service.enter(b.id, b.id)  # Host stands in the same world room as its visitor.
    visible = ok(client.get("/realtime/snapshot", headers=a.headers))["players"]
    assert any(p["player_id"] == b.id for p in visible)
    ok(client.post("/social/blocks", headers=b.headers, json={"target_id": a.id}))
    # A block hides the pair from each other without breaking the whole frame.
    visible = ok(client.get("/realtime/snapshot", headers=a.headers))["players"]
    assert not any(p["player_id"] == b.id for p in visible)


def test_remove_unblock_trade_cancel_decline_and_missing_offer(client, account, db):
    a, b = account(), account("trade_user")
    friends(client, a, b)
    ok(client.post(f"/social/friends/{b.id}", headers=a.headers, json={"action": "remove"}))
    assert client.get(f"/social/farms/{b.id}", headers=a.headers).status_code == 403
    ok(client.post("/social/blocks", headers=a.headers, json={"target_id": b.id}))
    ok(client.post(f"/social/blocks/{b.id}/remove", headers=a.headers))
    friends(client, a, b)
    payload = {"target_id": b.id, "request_id": "missing_offer", "offered_code": "wheat",
               "offered_quantity": 1, "wanted_code": "sweet_corn", "wanted_quantity": 1}
    assert client.post("/social/trades", headers=a.headers, json=payload).json()["error"] == "INSUFFICIENT_INVENTORY"
    add(client, a, "wheat")
    for action, user in (("cancel", a), ("decline", b)):
        payload["request_id"] = "trade_" + action
        trade = ok(client.post("/social/trades", headers=a.headers, json=payload))
        ok(client.post(f"/social/trades/{trade['id']}", headers=user.headers, json={"action": action}))
    assert InventoryService(db).repo.stack(a.id, "wheat").quantity == 1


def test_pet_ownership_consumption_and_fetch_replay(client, account, db):
    user = account()
    for character in ("girl", "catto"):
        ok(client.put("/profile", headers=user.headers, json={"character_code": character}))
    assert db.scalar(select(func.count()).select_from(PlayerPet)) == 1
    assert client.post("/pets/actions", headers=user.headers,
                       json={"action": "accessory", "item_code": "pet_ribbon"}).status_code == 400
    add(client, user, "pet_ribbon")
    ok(client.post("/pets/actions", headers=user.headers, json={"action": "accessory", "item_code": "pet_ribbon"}))
    ok(client.post("/shop/sell", headers=user.headers, json={"item_code": "pet_ribbon"}))
    db.expire_all()
    assert db.get(PlayerPet, user.id).accessory_code is None
    add(client, user, "basic_rod")
    assert client.post("/pets/actions", headers=user.headers,
                       json={"action": "feed", "item_code": "basic_rod"}).json()["error"] == "INVALID_FOOD"
    ok(client.post("/pets/actions", headers=user.headers, json={"action": "fetch_start"}))
    assert client.post("/pets/actions", headers=user.headers, json={"action": "fetch_finish"}).status_code == 429
    row = db.get(PlayerPet, user.id)
    row.last_interaction_at = row.fetch_started_at = utcnow() - timedelta(seconds=6)
    db.commit()
    assert ok(client.post("/pets/actions", headers=user.headers, json={"action": "fetch_finish"}))["affection"] == 3
    row.last_interaction_at = utcnow() - timedelta(seconds=6)
    db.commit()
    assert client.post("/pets/actions", headers=user.headers, json={"action": "fetch_finish"}).json()["error"] == "FETCH_NOT_READY"


def test_purchase_server_price_level_capacity_and_balance(client, account, db, monkeypatch):
    user = account()
    payload = {"item_code": "basic_rod", "quantity": 2, "request_id": "too_costly", "unit_price": 0}
    # The level gate is checked before price, so unlock the rod first.
    db.get(ItemRule, "basic_rod").required_level = 1
    db.commit()
    assert client.post("/shop/buy", headers=user.headers, json=payload).json()["error"] == "INSUFFICIENT_FUNDS"
    assert EconomyService(db).get(user.id).aura_balance == 10
    assert InventoryService(db).repo.stack(user.id, "basic_rod") is None
    db.get(ItemRule, "basic_rod").required_level = 2
    db.commit()
    payload.update(quantity=1, request_id="level_gate")
    assert client.post("/shop/buy", headers=user.headers, json=payload).json()["error"] == "LEVEL_internal"
    db.get(ItemRule, "basic_rod").required_level = 1
    db.commit()
    # A single shared pool: shrinking the base to 1 leaves only the level
    # increments, so the occupied slots are what block the purchase.
    monkeypatch.setattr(settings, "inventory_partition_slots", 1)
    service = InventoryService(db)
    capacity = service.capacity(user.id)
    codes = [
        code
        for code in db.scalars(
            select(ItemDefinition.item_code).order_by(ItemDefinition.item_code)
        )
        if code != "basic_rod"
    ]
    for code in codes[:capacity]:
        service.add_internal(user.id, code)
    db.commit()
    assert service.list(user.id).used_slots == capacity
    payload["request_id"] = "capacity_full"
    assert client.post("/shop/buy", headers=user.headers, json=payload).json()["error"] == "INVENTORY_FULL"
    db.expire_all()
    assert EconomyService(db).get(user.id).aura_balance == 10
    assert InventoryService(db).repo.stack(user.id, "basic_rod") is None


def test_drop_expiry_privacy_and_invite_notice_deduplication(client, account, db):
    a, b = account(), account("private_user")
    friends(client, a, b)
    drop = GroundDrop(player_id=a.id, item_code="river_carp", spot_code="campus_lake",
                      expires_at=utcnow() - timedelta(seconds=1))
    db.add(drop)
    db.commit()
    assert client.post(f"/fishing/drops/{drop.id}/claim", headers=b.headers).status_code == 404
    assert client.post(f"/fishing/drops/{drop.id}/claim", headers=a.headers).status_code == 409
    invite = ok(client.post("/social/invites", headers=a.headers, json={"target_id": b.id}))
    # Drive the real sweep instead of rewriting expires_at, so the row keeps its
    # "expires after it was created" invariant.
    tick(db, now=as_utc(db.get(Invite, invite["id"]).expires_at) + timedelta(seconds=1))
    assert db.scalar(select(func.count()).select_from(Notification).where(
        Notification.player_id == b.id, Notification.kind == "farm_invitation_expired")) == 1


def test_profile_cannot_write_progression_and_feedback_report_bounds(client, account, db):
    a, b = account(), account("reported_user")
    before = EconomyService(db).get(a.id).aura_balance
    ok(client.put("/profile", headers=a.headers, json={"aura_balance": 999999, "total_xp": 99999, "inventory": []}))
    db.expire_all()
    assert EconomyService(db).get(a.id).aura_balance == before
    assert EconomyService(db).xp(a.id).total_xp == 0
    assert client.post("/profile/feedback", headers=a.headers, json={"message": "x" * 2001}).status_code == 422
    assert client.post("/social/reports", headers=a.headers,
                       json={"target_id": b.id, "reason": "harassment", "details": "x" * 1001}).status_code == 422
    ok(client.post("/profile/feedback", headers=a.headers, json={"message": "Private feedback"}))
    assert client.get("/profile/feedback", headers=b.headers).status_code == 405


def test_account_deletion_preserves_claimed_gift(client, account, db):
    a, b = account(), account("gift_owner")
    friends(client, a, b)
    add(client, a, "wheat")
    gift = ok(client.post("/social/gifts", headers=a.headers,
                         json={"target_id": b.id, "request_id": "retained_gift", "item_code": "wheat"}))
    ok(client.post(f"/social/gifts/{gift['id']}/claim", headers=b.headers))
    payload = {"confirm_username": a.payload["username"], "password": "Wrong-Pass123!"}
    assert client.post("/profile/delete-account", headers=a.headers, json=payload).status_code == 403
    payload["password"] = a.payload["password"]
    ok(client.post("/profile/delete-account", headers=a.headers, json=payload))
    db.expire_all()
    assert InventoryService(db).repo.stack(b.id, "wheat").quantity == 1


def test_house_insufficient_balance_rolls_back(client, account, db):
    user = account()
    ok(client.post("/economy/xp/gain", headers=user.headers, json={"xp_amount": 100}))
    assert client.post("/housing/upgrade", headers=user.headers,
                       json={"expected_tier": 1}).json()["error"] == "INSUFFICIENT_FUNDS"
    assert ok(client.get("/housing", headers=user.headers))["house"]["tier"] == 1
    # 100 XP crosses level 2, so the once-only level reward is already paid.
    assert EconomyService(db).get(user.id).aura_balance == 10 + LEVEL_AURA_REWARDS[2]


@pytest.mark.parametrize("delay,caught", [(2, True), (2.001, False)])
def test_fishing_exact_window_and_server_reward(client, account, db, delay, caught):
    from app.modules.fishing.schemas import CastRequest
    from app.modules.fishing.service import FishingService
    from app.modules.fishing.models import FishingSession
    user = account()
    from app.modules.world.geometry import GEOMETRY
    x, y = GEOMETRY["water"][0]["points"][0]
    db.add(Presence(player_id=user.id, room="campus", x=x, y=y,
                    updated_at=utcnow(), sequence=0))
    db.commit()
    assert client.post("/fishing/cast", headers=user.headers,
                       json={"spot_code": "campus_lake", "rod_code": "basic_rod"}).json()["error"] == "ROD_REQUIRED"
    add(client, user, "basic_rod")
    db.get(ItemRule, "basic_rod").required_level = 2
    db.commit()
    assert client.post("/fishing/cast", headers=user.headers,
                       json={"spot_code": "campus_lake", "rod_code": "basic_rod"}).json()["error"] == "LEVEL_internal"
    db.get(ItemRule, "basic_rod").required_level = 1
    db.commit()
    service = FishingService(db)
    cast = service.cast(user.id, CastRequest(spot_code="campus_lake", rod_code="basic_rod"))
    assert "item_code" not in cast
    code = db.get(FishingSession, user.id).item_code
    result = service.catch(user.id, cast["cast_id"], cast["bite_at"] + timedelta(seconds=delay))
    assert result["caught"] is caught
    if caught:
        assert result["item_code"] == code
        assert result["xp"] == {"river_carp": 8, "golden_carp": 20, "lake_pearl": 25}[code]
        assert EconomyService(db).xp(user.id).total_xp == result["xp"]


def test_known_collision_polygon_rejects_move(client, account, db):
    from app.modules.world.geometry import GEOMETRY, inside
    user = account()
    points = GEOMETRY["collision"][0]["points"]
    # Sample the current pond, rather than hardcoding the retired map.
    xs, ys = zip(*points)
    x, y = next((x, y) for x in range(int(min(xs))+1, int(max(xs)), 20)
                for y in range(int(min(ys))+1, int(max(ys)), 20) if inside(x, y, points))
    assert inside(x, y, points)
    db.add(Presence(player_id=user.id, room="campus", x=x-1, y=y,
                    updated_at=utcnow() - timedelta(seconds=1), sequence=0))
    db.commit()
    assert client.post("/realtime/move", headers=user.headers,
                       json={"x": x, "y": y, "sequence": 1}).json()["error"] == "COLLISION"


@pytest.mark.parametrize("subject,status", [(None, 403), ("another-subject", 403), ("owned-subject", 200)])
def test_google_account_deletion_requires_matching_verified_identity(client, account, db, monkeypatch, subject, status):
    from app.modules.auth import oauth
    from app.modules.players.models import Player

    user = account()
    player = db.get(Player, user.id)
    player.hashed_password = None
    player.oauth_provider, player.oauth_provider_id = "google", "owned-subject"
    db.commit()
    # Unit boundary: production verification remains Google's signature/claim verifier.
    calls = []
    def verified_identity(raw):
        calls.append(raw)
        return oauth.GoogleIdentity(subject, user.payload["email"], "Verified", None, True)
    monkeypatch.setattr(oauth, "verify_google", verified_identity)
    payload = {"confirm_username": user.payload["username"]}
    if subject is not None:
        payload["google_id_token"] = "test-identity-token"
    assert client.post("/profile/delete-account", headers=user.headers, json=payload).status_code == status
    assert len(calls) == (0 if subject is None else 1)
    db.expire_all()
    assert (db.get(Player, user.id) is None) == (status == 200)
