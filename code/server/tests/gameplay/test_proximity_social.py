"""Behavioral coverage for room privacy, transactional socials and v2 sockets."""

from sqlalchemy import delete
from app.core.clock import utcnow
from app.core.config import settings
from app.modules.realtime.models import Presence, NearbyMessage
from app.modules.realtime.runtime import runtime, RealtimeRuntime
from app.modules.social.community_models import ChatReceipt


def ok(response):
    assert response.status_code == 200, response.text
    return response.json()["data"]


def friends(client, a, b):
    ok(client.post("/social/requests", headers=a.headers, json={"target_id": b.id}))
    ok(
        client.post(
            f"/social/friends/{a.id}", headers=b.headers, json={"action": "accept"}
        )
    )


def enter(client, user, **data):
    return ok(client.post("/realtime/enter", headers=user.headers, json=data))


def position(db, user, x, y=0):
    row = db.get(Presence, user.id, populate_existing=True)
    row.x, row.y, row.updated_at = x, y, utcnow()
    db.commit()


def test_proximity_exact_range_friend_policy_and_block(
    client, account, db, monkeypatch
):
    monkeypatch.setattr(settings, "voice_enabled", True)
    a, b, c = account("prox_a"), account("prox_b"), account("prox_c")
    friends(client, a, b)
    for user, x in ((a, 0), (b, 600), (c, 601)):
        enter(client, user)
        position(db, user, x)
    peers = {
        p["player_id"]: p
        for p in ok(client.get("/realtime/proximity", headers=a.headers))["nearby"]
    }
    assert peers[b.id]["can_text"] and peers[b.id]["can_voice"]
    assert not peers[c.id]["can_text"] and not peers[c.id]["can_voice"]
    ok(
        client.patch(
            "/social/preferences", headers=b.headers, json={"voice_privacy": "off"}
        )
    )
    peers = ok(client.get("/realtime/proximity", headers=a.headers))["nearby"]
    assert not next(p for p in peers if p["player_id"] == b.id)["can_voice"]
    ok(client.post("/social/blocks", headers=b.headers, json={"target_id": a.id}))
    assert b.id not in {
        p["player_id"]
        for p in ok(client.get("/realtime/proximity", headers=a.headers))["nearby"]
    }


def test_chat_retries_expiry_and_room_reentry_do_not_leak(client, account, db):
    a, b, late = account("chat_a"), account("chat_b"), account("chat_late")
    enter(client, a)
    enter(client, b)
    payload = {"body": " hello ", "request_id": "chat_request_01"}
    receipt = ok(client.post("/realtime/chat", headers=a.headers, json=payload))
    assert ok(client.post("/realtime/chat", headers=a.headers, json=payload)) == receipt
    assert (
        client.post(
            "/realtime/chat", headers=a.headers, json={**payload, "body": "changed"}
        ).status_code
        == 409
    )
    messages = ok(client.get("/realtime/snapshot", headers=b.headers))["messages"]
    assert len(messages) == 1 and messages[0]["body"] == "hello"
    assert messages[0]["room"] == "campus" and messages[0]["created_at"]
    enter(client, late)
    assert ok(client.get("/realtime/snapshot", headers=late.headers))["messages"] == []
    enter(client, b, owner_id=b.id)
    assert ok(client.get("/realtime/snapshot", headers=b.headers))["messages"] == []
    enter(client, b)
    assert ok(client.get("/realtime/snapshot", headers=b.headers))["messages"] == []
    db.execute(delete(NearbyMessage))
    db.commit()
    assert db.get(ChatReceipt, (a.id, "chat_request_01"))
    assert ok(client.post("/realtime/chat", headers=a.headers, json=payload)) == receipt


def test_chat_audience_exact_radius_and_block_after_acceptance(client, account, db):
    a, b, c = account("range_a"), account("range_b"), account("range_c")
    for user, x in ((a, 0), (b, 600), (c, 601)):
        enter(client, user)
        position(db, user, x)
    ok(client.post("/realtime/chat", headers=a.headers, json={"body": "hi"}))
    assert len(ok(client.get("/realtime/snapshot", headers=b.headers))["messages"]) == 1
    assert ok(client.get("/realtime/snapshot", headers=c.headers))["messages"] == []
    ok(client.post("/social/blocks", headers=b.headers, json={"target_id": a.id}))
    assert ok(client.get("/realtime/snapshot", headers=b.headers))["messages"] == []


def test_wishlist_gifts_reservation_claim_retry_and_privacy(client, account, db):
    a, b, c = account("gift_a"), account("gift_b"), account("gift_c")
    friends(client, a, b)
    friends(client, c, b)
    for user in (a, c):
        ok(
            client.post(
                "/inventory/add",
                headers=user.headers,
                json={"item_code": "wheat", "quantity": 5},
            )
        )
    entry = ok(
        client.put("/social/wishlist/wheat", headers=b.headers, json={"quantity": 3})
    )
    payload = {
        "target_id": b.id,
        "request_id": "wishlist_gift_01",
        "item_code": "wheat",
        "quantity": 2,
        "wishlist_entry_id": entry["id"],
        "wishlist_version": entry["version"],
    }
    gift = ok(client.post("/social/gifts", headers=a.headers, json=payload))
    assert (
        ok(client.post("/social/gifts", headers=a.headers, json=payload))["id"]
        == gift["id"]
    )
    assert ok(client.get("/social/gifts/requests/wishlist_gift_01", headers=a.headers))[
        "found"
    ]
    assert not ok(
        client.get("/social/gifts/requests/wishlist_gift_01", headers=c.headers)
    )["found"]
    current = ok(client.get("/social/wishlist", headers=b.headers))[0]
    assert (current["pending_quantity"], current["remaining_quantity"]) == (2, 1)
    assert (
        client.post(
            "/social/gifts",
            headers=c.headers,
            json={**payload, "request_id": "second_gift_01"},
        ).json()["error"]
        == "WISHLIST_CHANGED"
    )
    assert (
        client.post(
            "/social/gifts",
            headers=c.headers,
            json={
                **payload,
                "request_id": "second_gift_01",
                "wishlist_version": current["version"],
            },
        ).status_code
        == 409
    )
    assert (
        client.put(
            "/social/wishlist/wheat",
            headers=b.headers,
            json={"quantity": 1, "expected_version": current["version"]},
        ).status_code
        == 409
    )
    ok(client.post(f"/social/gifts/{gift['id']}/claim", headers=b.headers))
    current = ok(client.get("/social/wishlist", headers=b.headers))[0]
    assert (
        current["pending_quantity"],
        current["fulfilled_quantity"],
        current["remaining_quantity"],
    ) == (0, 2, 1)
    assert (
        client.post(f"/social/gifts/{gift['id']}/claim", headers=b.headers).json()[
            "error"
        ]
        == "ALREADY_CLAIMED"
    )
    assert (
        client.post(
            "/social/gifts",
            headers=a.headers,
            json={**payload, "wishlist_entry_id": None, "wishlist_version": None},
        ).status_code
        == 409
    )
    ok(
        client.patch(
            "/social/preferences",
            headers=b.headers,
            json={"wishlist_visibility": "private"},
        )
    )
    assert (
        client.get(f"/social/players/{b.id}/wishlist", headers=a.headers).status_code
        == 403
    )
    assert (
        client.patch(
            "/social/preferences", headers=b.headers, json={"voice_privacy": None}
        ).status_code
        == 422
    )
    assert (
        client.post(
            "/social/gifts",
            headers=a.headers,
            json={**payload, "request_id": "partial_link_01", "wishlist_version": None},
        ).status_code
        == 422
    )


def test_removed_wishlist_keeps_pending_gift(client, account):
    a, b = account("removed_a"), account("removed_b")
    friends(client, a, b)
    ok(
        client.post(
            "/inventory/add",
            headers=a.headers,
            json={"item_code": "wheat", "quantity": 1},
        )
    )
    entry = ok(
        client.put("/social/wishlist/wheat", headers=b.headers, json={"quantity": 1})
    )
    gift = ok(
        client.post(
            "/social/gifts",
            headers=a.headers,
            json={
                "target_id": b.id,
                "item_code": "wheat",
                "quantity": 1,
                "request_id": "removed_gift_01",
                "wishlist_entry_id": entry["id"],
                "wishlist_version": entry["version"],
            },
        )
    )
    entry = ok(client.get("/social/wishlist", headers=b.headers))[0]
    ok(
        client.delete(
            f"/social/wishlist/wheat?expected_version={entry['version']}",
            headers=b.headers,
        )
    )
    assert ok(client.get("/social/wishlist", headers=b.headers)) == []
    ok(client.post(f"/social/gifts/{gift['id']}/claim", headers=b.headers))


def test_websocket_v2_receipts_events_and_legacy(client, account):
    user = account("socket_v2")
    with client.websocket_connect("/realtime/ws") as ws:
        ws.send_json(
            {
                "type": "auth",
                "token": user.tokens["access_token"],
                "protocol_version": 2,
            }
        )
        first = ws.receive_json()
        assert first["connection_id"] and first["sequence"] == 1
        assert first["data"]["voice"]["joined"] is False
        assert {e["type"] for e in first["events"]} >= {
            "proximity.updated",
            "voice.updated",
            "social.updated",
        }
        ws.send_json(
            {"type": "chat", "request_id": "ws_text_01", "data": {"body": "hello"}}
        )
        for _ in range(10):
            reply = ws.receive_json()
            if reply.get("request_id") == "ws_text_01":
                break
        assert any(e["type"] == "chat.accepted" for e in reply["events"])
        assert any(e["type"] == "chat.message" for e in reply["events"])
        ws.send_json({"type": "voice.join", "request_id": "ws_voice_01"})
        for _ in range(10):
            reply = ws.receive_json()
            if reply.get("request_id") == "ws_voice_01":
                break
        assert reply["error"] == "VOICE_DISABLED"
        ws.send_json({"type": "heartbeat", "request_id": "still_here_01"})
        for _ in range(10):
            reply = ws.receive_json()
            if reply.get("request_id") == "still_here_01":
                break
        assert reply["type"] == "snapshot"
    with client.websocket_connect("/realtime/ws") as ws:
        ws.send_json({"type": "auth", "token": user.tokens["access_token"]})
        assert ws.receive_json()["type"] == "snapshot"


def policy(room="campus", peers=None, epoch=1):
    return dict(
        room=room,
        room_epoch=epoch,
        nearby=peers or [],
        voice_privacy="friends",
        proximity_prompts=True,
    )


def peer(pid, distance=100, allowed=True):
    return dict(
        player_id=pid,
        distance=distance,
        friend=True,
        can_text=distance <= 600,
        can_voice=allowed and distance <= 600,
    )


def test_voice_directional_permissions_leases_generations_and_encounters(monkeypatch):
    monkeypatch.setattr(settings, "voice_enabled", True)
    now = [100.0]
    rt = RealtimeRuntime(clock=lambda: now[0])
    owners = {i: rt.attach(i) for i in (1, 2, 3)}
    views = {
        1: policy(peers=[peer(2)]),
        2: policy(peers=[peer(1), peer(3)]),
        3: policy(peers=[peer(2)]),
    }
    for pid in owners:
        rt.apply(pid, owners[pid], rt.policy_revision(), views[pid])
        sid = rt.join(pid, owners[pid])
        assert rt.view(pid, owners[pid])["voice"]["muted"]
        rt.state(pid, owners[pid], sid, False, False, [])
    assert rt.audible(1, 2) == 1 and rt.audible(1, 3) == 0
    b = rt.view(2, owners[2])["voice"]["session_id"]
    rt.state(2, owners[2], b, False, False, [1])
    assert rt.audible(1, 2) == 0 and rt.audible(2, 1) == 1
    rt.state(2, owners[2], b, False, True, [])
    assert rt.audible(1, 2) == 0 and rt.audible(2, 1) == 0
    rt.dismiss(1, owners[1], 2)
    assert not rt.view(1, owners[1])["nearby"][0]["show_prompt"]
    revision = rt.policy_revision()
    rt.invalidate({1})
    assert not rt.apply(1, owners[1], revision, views[1])
    assert rt.audible(1, 2) == 0
    old = owners[1]
    owners[1] = rt.attach(1)
    rt.detach(1, old)
    assert rt.connection(1, owners[1])
    now[0] += 3
    assert rt.audible(2, 3) == 0
    rt.heartbeat(2, owners[2])
    assert not rt.view(2, owners[2])["voice"]["joined"]


def test_commit_revokes_voice_but_rollback_does_not(client, account, db, monkeypatch):
    from app.modules.social.community_models import SocialPreferences

    monkeypatch.setattr(settings, "voice_enabled", True)
    user = account("policy_user")
    generation = runtime.attach(user.id)
    try:
        runtime.apply(user.id, generation, runtime.policy_revision(), policy())
        runtime.join(user.id, generation)
        db.add(SocialPreferences(player_id=user.id, voice_privacy="off"))
        db.flush()
        db.rollback()
        assert runtime.view(user.id, generation)["voice"]["joined"]
        ok(
            client.patch(
                "/social/preferences",
                headers=user.headers,
                json={"voice_privacy": "off"},
            )
        )
        assert not runtime.view(user.id, generation)["voice"]["joined"]
    finally:
        runtime.detach(user.id, generation)


def test_stationary_heartbeat_refreshes_presence(client, account, db):
    from datetime import timedelta
    from app.core.clock import as_utc
    from app.modules.realtime.protocol import RealtimeProtocol

    user = account("idle_voice")
    enter(client, user)
    row = db.get(Presence, user.id)
    row.updated_at = utcnow() - timedelta(seconds=55)
    db.commit()
    generation = runtime.attach(user.id)
    try:
        reply = RealtimeProtocol(db).step(
            user.tokens["access_token"], {"type": "heartbeat"}, 2, generation
        )
        assert reply["type"] == "snapshot"
        assert (
            utcnow() - as_utc(db.get(Presence, user.id).updated_at)
        ).total_seconds() < 2
    finally:
        runtime.detach(user.id, generation)


def test_guest_kick_revokes_voice_and_pending_audience(
    client, account, db, monkeypatch
):
    monkeypatch.setattr(settings, "voice_enabled", True)
    host, guest = account("voice_host"), account("voice_guest")
    friends(client, host, guest)
    enter(client, host, owner_id=host.id)
    invitation = ok(
        client.post(
            "/farm/visiting/invitations",
            headers=host.headers,
            json={"target_id": guest.id},
        )
    )
    visit = ok(
        client.post(
            f"/farm/visiting/invitations/{invitation['id']}/accept",
            headers=guest.headers,
        )
    )
    enter(client, guest, owner_id=host.id)
    generation = runtime.attach(guest.id)
    try:
        runtime.apply(
            guest.id,
            generation,
            runtime.policy_revision(),
            policy(room=f"world:{visit['world_id']}"),
        )
        runtime.join(guest.id, generation)
        ok(
            client.delete(
                f"/farm/visiting/visitors/{visit['visit_session_id']}",
                headers=host.headers,
            )
        )
        assert not runtime.view(guest.id, generation)["voice"]["joined"]
        assert not ok(client.get("/realtime/proximity", headers=host.headers))["nearby"]
        assert (
            client.get("/realtime/proximity", headers=guest.headers).json()["error"]
            == "VISIT_ENDED"
        )
    finally:
        runtime.detach(guest.id, generation)


def test_wishlist_failed_gift_rolls_back_allocation_and_can_restore_removed_entry(
    client, account
):
    a, b = account("empty_donor"), account("wish_owner")
    friends(client, a, b)
    entry = ok(
        client.put("/social/wishlist/wheat", headers=b.headers, json={"quantity": 2})
    )
    failed = client.post(
        "/social/gifts",
        headers=a.headers,
        json={
            "target_id": b.id,
            "item_code": "wheat",
            "quantity": 1,
            "request_id": "failed_gift_01",
            "wishlist_entry_id": entry["id"],
            "wishlist_version": entry["version"],
        },
    )
    assert failed.status_code != 200
    assert ok(client.get("/social/wishlist", headers=b.headers))[0] == entry
    assert not ok(
        client.get("/social/gifts/requests/failed_gift_01", headers=a.headers)
    )["found"]
    ok(
        client.delete(
            f"/social/wishlist/wheat?expected_version={entry['version']}",
            headers=b.headers,
        )
    )
    removed = ok(client.get("/social/wishlist/wheat", headers=b.headers))
    assert not removed["active"]
    assert client.get("/social/wishlist/wheat", headers=a.headers).status_code == 404
    restored = ok(
        client.put(
            "/social/wishlist/wheat",
            headers=b.headers,
            json={"quantity": 2, "expected_version": removed["version"]},
        )
    )
    assert restored["active"] and restored["id"] == entry["id"]


def test_websocket_voice_join_state_and_origin(client, account, monkeypatch):
    import pytest
    from starlette.websockets import WebSocketDisconnect

    pytest.importorskip("aiortc")
    monkeypatch.setattr(settings, "voice_enabled", True)
    user = account("voice_socket")
    with pytest.raises(WebSocketDisconnect):
        with client.websocket_connect(
            "/realtime/ws", headers={"origin": "https://untrusted.example"}
        ):
            pass
    with client.websocket_connect("/realtime/ws") as ws:
        ws.send_json(
            {
                "type": "auth",
                "token": user.tokens["access_token"],
                "protocol_version": 2,
            }
        )
        ws.receive_json()

        def command(kind, request_id, data=None):
            ws.send_json({"type": kind, "request_id": request_id, "data": data or {}})
            for _ in range(20):
                reply = ws.receive_json()
                if reply.get("request_id") == request_id:
                    return reply
            raise AssertionError("Command did not receive a correlated reply")

        joined = command("voice.join", "voice_join_01")
        ready = next(e for e in joined["events"] if e["type"] == "voice.ready")
        sid = ready["data"]["session_id"]
        assert joined["data"]["voice"]["muted"]
        state = command(
            "voice.state",
            "voice_state_01",
            {"session_id": sid, "muted": False, "deafened": True},
        )
        assert state["data"]["voice"]["muted"] and state["data"]["voice"]["deafened"]
        left = command("voice.leave", "voice_leave_01")
        assert not left["data"]["voice"]["joined"]
        stale = command(
            "voice.state", "voice_stale_01", {"session_id": sid, "muted": False}
        )
        assert stale["error"] == "VOICE_SESSION_EXPIRED"
