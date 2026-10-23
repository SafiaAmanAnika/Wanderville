from sqlalchemy import select
from app.modules.world.models import WorldState
from datetime import timedelta
import pytest
from app.core.clock import utcnow
from app.core.exceptions import AppError
from app.core.config import settings
from app.core.progression import (
    FISH_XP_BY_ITEM,
    LEVEL_AURA_REWARDS,
    SELL_XP_PER_UNIT,
    slot_capacity,
)
from app.modules.economy.service import EconomyService
from app.modules.inventory.service import InventoryService
from app.modules.players.repository import PlayerRepository
from app.db.session import transaction
from app.modules.social.models import Gift, Trade
from app.modules.progression.service import ProgressionService
from app.modules.profile.models import PlayerProfile
from app.modules.fishing.service import FishingService
from app.modules.fishing.schemas import CastRequest
from app.modules.fishing.models import FishingSession
from app.modules.realtime.models import Presence
from app.modules.world.geometry import GEOMETRY, at_water
from app.modules.world.models import CAMPUS_SPAWN


def data(response):
    assert response.status_code == 200, response.text
    return response.json()["data"]


def add(client, user, code, quantity=1):
    return data(
        client.post(
            "/inventory/add",
            headers=user.headers,
            json={"item_code": code, "quantity": quantity},
        )
    )


def funds(client, user, amount=1000):
    data(client.post("/economy/earn", headers=user.headers, json={"amount": amount}))


def fill_slots(db, user, exclude=()):
    """Occupy every slot the player's level allows with distinct stacks."""
    from sqlalchemy import select as _select

    from app.modules.inventory.models import InventoryItem, ItemDefinition

    service = InventoryService(db)
    capacity = service.capacity(user.id)
    rows = list(
        db.execute(
            _select(InventoryItem.item_code, InventoryItem.stack_no).where(
                InventoryItem.player_id == user.id
            )
        )
    )
    owned = {code for code, _ in rows}
    codes = [
        code
        for code in db.scalars(
            _select(ItemDefinition.item_code).order_by(ItemDefinition.item_code)
        )
        if code not in owned and code not in set(exclude)
    ]
    room = capacity - len(rows)
    assert len(codes) >= room, "catalog too small to fill the inventory"
    for code in codes[:room]:
        service.add_internal(user.id, code)
    db.commit()
    assert service.list(user.id).used_slots == capacity
    return service


def befriend(client, a, b):
    data(client.post("/social/requests", headers=a.headers, json={"target_id": b.id}))
    data(
        client.post(
            f"/social/friends/{a.id}", headers=b.headers, json={"action": "accept"}
        )
    )


def test_purchase_idempotency_and_rollback(client, account, db, reach_level):
    a = account()
    funds(client, a)
    reach_level(a, 5)
    request = {"request_id": "purchase_01", "item_code": "basic_rod", "quantity": 1}
    first = data(client.post("/shop/buy", headers=a.headers, json=request))
    assert data(client.post("/shop/buy", headers=a.headers, json=request)) == first
    assert InventoryService(db).repo.stack(a.id, "basic_rod").quantity == 1
    # Levelling to 5 paid the one-off level 2 Aura reward on the way up.
    assert (
        EconomyService(db).get(a.id).aura_balance == 1000 + LEVEL_AURA_REWARDS[2]
    )
    request["quantity"] = 2
    assert client.post("/shop/buy", headers=a.headers, json=request).status_code == 409
    # Fill the first rod stack, then a second one: levels widen the shared pool
    # instead of capping an item at a single row.
    add(client, a, "basic_rod", 98)
    add(client, a, "basic_rod", 99)
    assert InventoryService(db).list(a.id).used_slots == 2
    fill_slots(db, a, exclude=("basic_rod",))
    before = EconomyService(db).get(a.id).aura_balance
    request.update(request_id="purchase_02", quantity=1)
    assert (
        client.post("/shop/buy", headers=a.headers, json=request).json()["error"]
        == "INVENTORY_FULL"
    )
    db.expire_all()
    assert EconomyService(db).get(a.id).aura_balance == before


def test_store_gear_is_internal_below_level_five(client, account, db, reach_level):
    a = account()
    funds(client, a)
    assert (
        client.post(
            "/shop/buy",
            headers=a.headers,
            json={"request_id": "locked_rod", "item_code": "basic_rod", "quantity": 1},
        ).json()["error"]
        == "LEVEL_internal"
    )
    reach_level(a, 5)
    data(
        client.post(
            "/shop/buy",
            headers=a.headers,
            json={
                "request_id": "unlocked_rod",
                "item_code": "basic_rod",
                "quantity": 1,
            },
        )
    )
    # Re-selling store stock pays Aura but never XP, so it cannot be farmed.
    before = EconomyService(db).xp(a.id).total_xp
    data(
        client.post(
            "/shop/sell",
            headers=a.headers,
            json={"item_code": "basic_rod", "quantity": 1},
        )
    )
    assert EconomyService(db).xp(a.id).total_xp == before


def test_sale_collection_and_shared_capacity(client, account, db, monkeypatch):
    monkeypatch.setattr(settings, "inventory_partition_slots", 1)
    a = account()
    add(client, a, "river_carp", 2)
    assert data(client.get("/shop/collection?fish_only=true", headers=a.headers))[1][
        "obtained"
    ]
    result = data(
        client.post(
            "/shop/sell",
            headers=a.headers,
            json={"item_code": "river_carp", "quantity": 2},
        )
    )
    assert result["aura_earned"] == 24
    assert InventoryService(db).repo.stack(a.id, "river_carp") is None
    assert next(
        i
        for i in data(client.get("/shop/collection", headers=a.headers))
        if i["item_code"] == "river_carp"
    )["obtained"]
    # Selling fish pays sale XP; the base pool is shared, not per category.
    assert EconomyService(db).xp(a.id).total_xp == SELL_XP_PER_UNIT * 2
    service = InventoryService(db)
    # The base pool is now 1 and the level still adds its own increment.
    assert service.capacity(a.id) == slot_capacity(1, base=1) == 4
    for code in ("river_carp", "golden_carp", "lake_pearl", "moonflower"):
        add(client, a, code)
    assert InventoryService(db).list(a.id).used_slots == 4
    assert (
        client.post(
            "/inventory/add", headers=a.headers, json={"item_code": "wheat"}
        ).json()["error"]
        == "INVENTORY_FULL"
    )


def test_profile_house_pet_and_preferences(client, account, db):
    a = account()
    assert data(client.get("/housing", headers=a.headers))["house"]["tier"] == 1
    data(
        client.put(
            "/profile",
            headers=a.headers,
            json={
                "character_code": "girl",
                "music_volume": 25,
                "display_name": "Tayma",
            },
        )
    )
    assert data(client.get("/pets", headers=a.headers))["name"] == "Mochi"
    assert (
        client.put(
            "/profile", headers=a.headers, json={"music_volume": None}
        ).status_code
        == 422
    )
    add(client, a, "pet_biscuit")
    pet = data(
        client.post(
            "/pets/actions",
            headers=a.headers,
            json={"action": "feed", "item_code": "pet_biscuit"},
        )
    )
    assert pet["affection"] == 10
    assert InventoryService(db).repo.stack(a.id, "pet_biscuit") is None
    data(
        client.post(
            "/pets/actions",
            headers=a.headers,
            json={"action": "rename", "name": "Luna"},
        )
    )
    funds(client, a)
    assert (
        client.post(
            "/housing/upgrade", headers=a.headers, json={"expected_tier": 1}
        ).json()["error"]
        == "LEVEL_internal"
    )
    data(client.post("/economy/xp/gain", headers=a.headers, json={"xp_amount": 100}))
    assert (
        data(
            client.post(
                "/housing/upgrade", headers=a.headers, json={"expected_tier": 1}
            )
        )["tier"]
        == 2
    )
    assert (
        client.post(
            "/housing/upgrade", headers=a.headers, json={"expected_tier": 1}
        ).status_code
        == 409
    )


def test_friend_auth_and_blocking(client, account):
    a, b, c = account(), account("second_user"), account("third_user")
    assert (
        client.post(
            "/social/requests", headers=a.headers, json={"target_id": a.id}
        ).status_code
        == 400
    )
    data(client.post("/social/requests", headers=a.headers, json={"target_id": b.id}))
    assert (
        client.post(
            "/social/requests", headers=b.headers, json={"target_id": a.id}
        ).status_code
        == 409
    )
    assert (
        client.post(
            f"/social/friends/{b.id}", headers=a.headers, json={"action": "accept"}
        ).status_code
        == 403
    )
    data(
        client.post(
            f"/social/friends/{a.id}", headers=b.headers, json={"action": "accept"}
        )
    )
    assert len(data(client.get("/social/friends", headers=a.headers))) == 1
    assert client.post(f"/social/visit/{a.id}", headers=c.headers).status_code == 403
    data(client.post("/social/blocks", headers=b.headers, json={"target_id": a.id}))
    assert data(client.get("/social/friends", headers=a.headers)) == []
    assert (
        client.post(
            "/social/requests", headers=a.headers, json={"target_id": b.id}
        ).status_code
        == 403
    )
    assert data(client.get("/social/search?q=second", headers=a.headers)) == []


def test_gift_escrow_full_inventory_and_duplicate(client, account, db):
    a, b, c = account(), account("second_user"), account("third_user")
    befriend(client, a, b)
    add(client, a, "wheat", 3)
    add(client, b, "wheat", 99)
    payload = {
        "target_id": b.id,
        "item_code": "wheat",
        "quantity": 2,
        "request_id": "gift_0001",
    }
    gift = data(client.post("/social/gifts", headers=a.headers, json=payload))
    assert (
        data(client.post("/social/gifts", headers=a.headers, json=payload))["id"]
        == gift["id"]
    )
    assert InventoryService(db).repo.stack(a.id, "wheat").quantity == 1
    assert (
        client.post(f"/social/gifts/{gift['id']}/claim", headers=c.headers).status_code
        == 404
    )
    # b's wheat is one full stack but slots remain, so the gift is accepted
    # by opening a second stack; capacity is only refused once it is full.
    data(client.post(f"/social/gifts/{gift['id']}/claim", headers=b.headers))
    assert db.get(Gift, gift["id"]).claimed
    assert (
        client.post(f"/social/gifts/{gift['id']}/claim", headers=b.headers).status_code
        == 409
    )

    add(client, a, "corn", 2)
    second = data(
        client.post(
            "/social/gifts",
            headers=a.headers,
            json={
                "target_id": b.id,
                "item_code": "corn",
                "quantity": 1,
                "request_id": "gift_0002",
            },
        )
    )
    fill_slots(db, b, exclude=("corn",))
    assert (
        client.post(f"/social/gifts/{second['id']}/claim", headers=b.headers).json()[
            "error"
        ]
        == "INVENTORY_FULL"
    )
    assert not db.get(Gift, second["id"]).claimed
    # The gift stays in escrow until the receiver empties a whole stack.
    data(
        client.post(
            "/inventory/remove",
            headers=b.headers,
            json={"item_code": "wheat", "quantity": 99},
        )
    )
    data(client.post(f"/social/gifts/{second['id']}/claim", headers=b.headers))
    assert db.get(Gift, second["id"]).claimed


def test_trade_atomic_failure_and_acceptance(client, account, db):
    a, b = account(), account("second_user")
    befriend(client, a, b)
    add(client, a, "wheat", 2)
    add(client, b, "corn", 2)
    payload = {
        "target_id": b.id,
        "offered_code": "wheat",
        "offered_quantity": 2,
        "wanted_code": "corn",
        "wanted_quantity": 2,
        "request_id": "trade_001",
    }
    trade = data(client.post("/social/trades", headers=a.headers, json=payload))
    assert (
        client.post(
            f"/social/trades/{trade['id']}",
            headers=a.headers,
            json={"action": "accept"},
        ).status_code
        == 403
    )
    data(
        client.post(
            "/inventory/remove",
            headers=b.headers,
            json={"item_code": "corn", "quantity": 1},
        )
    )
    assert (
        client.post(
            f"/social/trades/{trade['id']}",
            headers=b.headers,
            json={"action": "accept"},
        ).status_code
        == 400
    )
    assert InventoryService(db).repo.stack(a.id, "wheat").quantity == 2
    assert db.get(Trade, trade["id"]).status == "pending"
    add(client, b, "corn")
    data(
        client.post(
            f"/social/trades/{trade['id']}",
            headers=b.headers,
            json={"action": "accept"},
        )
    )
    db.expire_all()
    assert InventoryService(db).repo.stack(a.id, "corn").quantity == 2
    assert InventoryService(db).repo.stack(b.id, "wheat").quantity == 2
    assert (
        client.post(
            f"/social/trades/{trade['id']}",
            headers=b.headers,
            json={"action": "accept"},
        ).status_code
        == 409
    )


def lake_presence(db, pid):
    # Known water interaction polygon from the uploaded map; test setup only.
    x, y = GEOMETRY["water"][0]["points"][0]
    assert at_water(x, y)
    db.add(
        Presence(
            player_id=pid,
            room="campus",
            x=x,
            y=y,
            updated_at=utcnow(),
            sequence=0,
        )
    )
    db.commit()


def test_fishing_timing_rewards_and_no_replay(client, account, db, reach_level):
    a = account()
    reach_level(a, 5)
    add(client, a, "basic_rod")
    lake_presence(db, a.id)
    service = FishingService(db)
    cast = service.cast(
        a.id, CastRequest(spot_code="campus_lake", rod_code="basic_rod")
    )
    with pytest.raises(AppError, match="Wait for the bite"):
        service.catch(a.id, cast["cast_id"])
    result = service.catch(
        a.id, cast["cast_id"], cast["bite_at"] + timedelta(seconds=1)
    )
    assert result["caught"] and result["xp"] in FISH_XP_BY_ITEM.values()
    with pytest.raises(AppError):
        service.catch(a.id, cast["cast_id"], cast["bite_at"] + timedelta(seconds=1))


def test_fishing_requires_level_five(client, account, db):
    a = account()
    add(client, a, "basic_rod")
    lake_presence(db, a.id)
    with pytest.raises(AppError) as failure:
        FishingService(db).cast(
            a.id, CastRequest(spot_code="campus_lake", rod_code="basic_rod")
        )
    assert failure.value.code == "LEVEL_internal"


def test_fishing_full_inventory_drop_and_expiry(client, account, db, reach_level):
    a = account()
    reach_level(a, 5)
    add(client, a, "basic_rod")
    lake_presence(db, a.id)
    service = FishingService(db)
    cast = service.cast(
        a.id, CastRequest(spot_code="campus_lake", rod_code="basic_rod")
    )
    code = db.get(FishingSession, a.id).item_code
    # Every slot is taken by a different item, so the pending catch has nowhere
    # to go even though it could otherwise share the item's own stack.
    fill_slots(db, a, exclude=(code,))
    result = service.catch(a.id, cast["cast_id"], cast["bite_at"])
    drop = result["ground_drop"]
    assert drop
    assert (
        client.post(f"/fishing/drops/{drop['id']}/claim", headers=a.headers).json()[
            "error"
        ]
        == "INVENTORY_FULL"
    )
    data(
        client.post(
            "/inventory/remove",
            headers=a.headers,
            json={"item_code": "basic_rod", "quantity": 1, "confirmed": True},
        )
    )
    data(client.post(f"/fishing/drops/{drop['id']}/claim", headers=a.headers))
    assert (
        client.post(f"/fishing/drops/{drop['id']}/claim", headers=a.headers).status_code
        == 409
    )


def test_login_and_goals_reward_exactly_once(client, account, db):
    a = account()
    initial = EconomyService(db).get(a.id).aura_balance
    with transaction(db):
        PlayerRepository(db).lock(a.id)
        ProgressionService(db).login(a.id)
        ProgressionService(db).record(a.id, "harvest")
    assert EconomyService(db).get(a.id).aura_balance == initial + 10
    with transaction(db):
        PlayerRepository(db).lock(a.id)
        ProgressionService(db).record(a.id, "harvest")
    assert EconomyService(db).get(a.id).aura_balance == initial + 10
    with transaction(db):
        PlayerRepository(db).lock(a.id)
        ProgressionService(db).record(a.id, "harvest")
    assert EconomyService(db).get(a.id).aura_balance == initial + 25


def test_notifications_private_and_dismissed(client, account, db):
    a, b = account(), account("second_user")
    data(client.post("/social/requests", headers=a.headers, json={"target_id": b.id}))
    inbox = data(client.get("/notifications", headers=b.headers))
    assert inbox["unread_count"] == 1
    nid = inbox["items"][0]["id"]
    assert (
        client.post(f"/notifications/{nid}", headers=a.headers, json={}).status_code
        == 404
    )
    data(
        client.post(f"/notifications/{nid}", headers=b.headers, json={"dismiss": True})
    )
    assert data(client.get("/notifications", headers=b.headers))["unread_count"] == 0
    assert data(client.get("/notifications", headers=b.headers))["items"] == []


def test_realtime_radius_blocking_and_sequence(client, account, db):
    a, b, c = account(), account("second_user"), account("third_user")
    for u in (a, b, c):
        data(client.post("/realtime/enter", headers=u.headers, json={}))
    row = db.get(Presence, c.id)
    row.x += 5000
    db.commit()
    data(
        client.post(
            "/realtime/chat", headers=a.headers, json={"body": "hello shit friend"}
        )
    )
    assert (
        data(client.get("/realtime/snapshot", headers=b.headers))["messages"][0]["body"]
        == "hello **** friend"
    )
    assert data(client.get("/realtime/snapshot", headers=c.headers))["messages"] == []
    assert (
        client.post(
            "/realtime/move",
            headers=a.headers,
            json={"x": 90000, "y": 90000, "sequence": 1},
        ).status_code
        == 400
    )
    data(
        client.post(
            "/realtime/move",
            headers=a.headers,
            json={"x": CAMPUS_SPAWN[0], "y": CAMPUS_SPAWN[1], "sequence": 1},
        )
    )
    assert (
        client.post(
            "/realtime/move",
            headers=a.headers,
            json={"x": CAMPUS_SPAWN[0], "y": CAMPUS_SPAWN[1], "sequence": 1},
        ).status_code
        == 409
    )
    data(client.post("/social/blocks", headers=b.headers, json={"target_id": a.id}))
    assert data(client.get("/realtime/snapshot", headers=b.headers))["messages"] == []


def test_tutorial_refill_and_account_delete(client, account, db):
    a = account()
    assert (
        data(
            client.post(
                "/profile/tutorial", headers=a.headers, json={"expected_step": 0}
            )
        )["step"]
        == 1
    )
    assert (
        client.post(
            "/profile/tutorial", headers=a.headers, json={"expected_step": 0}
        ).status_code
        == 409
    )
    assert data(client.post("/profile/hints/farming", headers=a.headers))["show_hint"]
    assert not data(client.post("/profile/hints/farming", headers=a.headers))[
        "show_hint"
    ]
    lake_presence(db, a.id)
    db.get(PlayerProfile, a.id).water_charges = 0
    db.commit()
    assert data(client.post("/farm/refill", headers=a.headers))["water_remaining"] == 1
    assert (
        client.post(
            "/profile/delete-account",
            headers=a.headers,
            json={"confirm_username": "wrong", "password": a.payload["password"]},
        ).status_code
        == 400
    )
    data(
        client.post(
            "/profile/delete-account",
            headers=a.headers,
            json={
                "confirm_username": a.payload["username"],
                "password": a.payload["password"],
            },
        )
    )
    assert client.get("/profile", headers=a.headers).status_code == 401
    db.expire_all()
    assert db.get(PlayerProfile, a.id) is None


def test_new_seed_maps_to_produce(client, account, db):
    a = account()
    add(client, a, "wheat_seed")
    plot = data(
        client.post(
            "/farm/plant",
            headers=a.headers,
            json={"x": 1, "y": 1, "item_code": "wheat_seed"},
        )
    )["plot"]
    assert plot["item_code"] == "wheat"
    assert InventoryService(db).repo.stack(a.id, "wheat_seed") is None


def test_events_expiry_replay_and_worker(client, account, db):
    from app.modules.events.models import WorldEvent
    from app.modules.world.worker import tick

    a = account()
    db.add(
        WorldEvent(
            code="test_event",
            title="Test",
            starts_at=utcnow() - timedelta(minutes=1),
            ends_at=utcnow() + timedelta(minutes=1),
            item_code="lake_pearl",
            quantity=1,
        )
    )
    db.commit()
    data(client.post("/events/test_event/claim", headers=a.headers))
    assert client.post("/events/test_event/claim", headers=a.headers).status_code == 409
    assert tick(db) == 0


@pytest.mark.parametrize(
    "path",
    [
        "/shop",
        "/profile",
        "/pets",
        "/housing",
        "/notifications",
        "/social/friends",
        "/events",
        "/fishing/spots",
        "/progression/goals",
        "/realtime/snapshot",
    ],
)
def test_new_routes_require_auth(client, path):
    assert client.get(path).status_code == 401


def test_websocket_auth_and_snapshot(client, account):
    a = account()
    with client.websocket_connect("/realtime/ws") as ws:
        ws.send_json({"type": "auth", "token": a.tokens["access_token"]})
        result = ws.receive_json()
        assert result["type"] == "snapshot"
        assert result["data"]["players"][0]["player_id"] == a.id
        ws.send_json({"type": "move", "data": {"x": CAMPUS_SPAWN[0], "y": CAMPUS_SPAWN[1], "sequence": 1}})
        assert ws.receive_json()["type"] == "snapshot"
    with client.websocket_connect("/realtime/ws") as ws:
        ws.send_json({"type": "auth", "token": "invalid"})
        assert ws.receive_json()["status"] == 401


def test_worker_rain_and_ready_notifications_once(client, account, db):
    from app.modules.farming.service import FarmingService
    from app.modules.farming.schemas import PlantRequest
    from app.modules.world.worker import tick
    from app.modules.notifications.models import Notification

    a = account()
    add(client, a, "wheat")
    start = utcnow()
    farm = FarmingService(db)
    farm.plant(a.id, PlantRequest(x=1, y=1, item_code="wheat"), start)
    db.get(WorldState, 1).weather = "rain"
    db.commit()
    tick(db, start)
    for step in range(1, 4):
        tick(db, start + timedelta(seconds=60 * step))
    tick(db, start + timedelta(seconds=240))
    notices = list(
        db.scalars(
            select(Notification).where(
                Notification.player_id == a.id, Notification.kind == "crop_ready"
            )
        )
    )
    assert len(notices) == 1
    assert farm.list(a.id, start + timedelta(seconds=240)).plots[0].ready
    assert db.get(PlayerProfile, a.id).water_charges == 20


def test_streak_gap_and_daily_task_rollover(client, account, db):
    from app.modules.progression.models import LoginStreak, GoalProgress

    a = account()
    service = ProgressionService(db)
    now = utcnow()
    with transaction(db):
        PlayerRepository(db).lock(a.id)
        service.login(a.id, now + timedelta(days=1))
    assert db.get(LoginStreak, a.id).streak == 2
    with transaction(db):
        PlayerRepository(db).lock(a.id)
        service.login(a.id, now + timedelta(days=3))
        service.record(a.id, "plant", 5, now)
        service.record(a.id, "plant", 5, now + timedelta(minutes=40))
    assert db.get(LoginStreak, a.id).streak == 1
    assert (
        len(
            list(
                db.scalars(
                    select(GoalProgress).where(
                        GoalProgress.player_id == a.id,
                        GoalProgress.goal_code == "daily_plant",
                    )
                )
            )
        )
        == 2
    )


def test_frozen_lake_and_missed_bite(client, account, db, reach_level):
    a = account()
    reach_level(a, 5)
    add(client, a, "basic_rod")
    lake_presence(db, a.id)
    world = db.get(WorldState, 1)
    world.current_season = "winter"
    world.season_started_at = utcnow()
    db.commit()
    assert (
        client.post(
            "/fishing/cast",
            headers=a.headers,
            json={"spot_code": "campus_lake", "rod_code": "basic_rod"},
        ).json()["error"]
        == "FROZEN_LAKE"
    )
    world.current_season = "summer"
    db.commit()
    before_xp = EconomyService(db).xp(a.id).total_xp
    service = FishingService(db)
    cast = service.cast(
        a.id, CastRequest(spot_code="campus_lake", rod_code="basic_rod")
    )
    assert (
        service.catch(a.id, cast["cast_id"], cast["expires_at"] + timedelta(seconds=1))[
            "caught"
        ]
        is False
    )
    assert EconomyService(db).xp(a.id).total_xp == before_xp


def test_rare_discard_requires_confirmation(client, account):
    a = account()
    add(client, a, "lake_pearl")
    assert (
        client.post(
            "/inventory/remove", headers=a.headers, json={"item_code": "lake_pearl"}
        ).json()["error"]
        == "CONFIRMATION_REQUIRED"
    )
    data(
        client.post(
            "/inventory/remove",
            headers=a.headers,
            json={"item_code": "lake_pearl", "confirmed": True},
        )
    )


def test_invites_messages_and_private_profiles(client, account, db):
    from app.modules.social.models import FarmInvitation

    a, b = account(), account("second_user")
    befriend(client, a, b)
    invite = data(
        client.post("/social/invites", headers=a.headers, json={"target_id": b.id})
    )
    row = db.get(FarmInvitation, invite["id"])
    # Age the whole offer rather than only expires_at, so the row keeps its
    # "expires after it was created" invariant.
    row.created_at = utcnow() - timedelta(days=1)
    row.expires_at = utcnow() - timedelta(seconds=1)
    db.commit()
    assert (
        client.post(f"/social/invites/{row.id}/accept", headers=b.headers).status_code
        == 409
    )
    data(
        client.post(
            "/social/messages",
            headers=a.headers,
            json={"target_id": b.id, "body": "hello damn friend"},
        )
    )
    messages = data(client.get(f"/social/messages/{a.id}", headers=b.headers))
    assert messages[0]["body"] == "hello **** friend"
    profile = data(client.get("/social/friends", headers=b.headers))[0]
    assert "email" not in profile and "inventory" not in profile
