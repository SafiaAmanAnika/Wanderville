"""Cutting trees for wood: one forest per player, regrown when a season is cleared."""
import math
import pytest

from app.core.clock import utcnow
from app.modules.realtime.models import Presence
from app.modules.trees.models import CutTree
from app.modules.trees.service import REGROW_COUNT, WOOD_PER_TREE, TreeService
from app.modules.world.geometry import GEOMETRY, at_water, walkable
from app.modules.world.models import WorldState


def data(response):
    assert response.status_code == 200, response.text
    return response.json()["data"]


def stand(db, pid, x, y):
    row = db.get(Presence, pid)
    if row is None:
        db.add(Presence(player_id=pid, room="campus", x=x, y=y, updated_at=utcnow(), sequence=0))
    else:
        row.x, row.y, row.updated_at = x, y, utcnow()
    db.commit()


def season(db, name):
    world = db.get(WorldState, 1)
    world.current_season = name
    world.season_started_at = utcnow()
    db.commit()


def wood(client, user):
    items = data(client.get("/inventory/", headers=user.headers))["items"]
    return sum(i["quantity"] for i in items if i["item_code"] == "wood")


def summer_tree():
    return next(t for t in GEOMETRY["trees"] if t["season"] == "summer")


@pytest.mark.parametrize("near", [True, False])
def test_chop_uses_live_memory_position_not_saved_spawn(client, account, db, monkeypatch, near):
    from app.core.config import settings
    from app.modules.realtime import position_projection
    monkeypatch.setattr(settings, "presence_backend", "memory")
    season(db, "summer")
    me = account("live_cutter")
    tree = summer_tree()
    # The durable coordinate is opposite to the current live coordinate.
    stand(db, me.id, tree["x"] + (1000 if near else 0), tree["y"])
    row = db.get(Presence, me.id)
    position_projection.commit(me.id, row.room, tree["x"] + (0 if near else 1000),
                               tree["y"], 1, row.room_epoch, utcnow())
    response = client.post("/trees/chop", headers=me.headers, json={"tree_id": tree["id"]})
    if near:
        assert data(response)["wood"] == WOOD_PER_TREE
        assert wood(client, me) == WOOD_PER_TREE
    else:
        assert response.json()["error"] == "TREE_TOO_FAR"
        assert wood(client, me) == 0


def test_every_season_has_map_trees_with_trunks_in_the_world():
    seasons = {t["season"] for t in GEOMETRY["trees"]}
    assert seasons == {"summer", "autumn", "winter", "spring"}
    xs = [p[0] for p in GEOMETRY["boundary"]]
    ys = [p[1] for p in GEOMETRY["boundary"]]
    for tree in GEOMETRY["trees"]:
        assert min(xs) - 600 <= tree["x"] <= max(xs) + 600, tree
        assert min(ys) - 600 <= tree["y"] <= max(ys) + 600, tree
        assert tree["scene"].startswith("res://Scenes/trees/" + tree["season"] + "/"), tree


def test_chop_gives_fifteen_wood_once_and_only_for_that_player(client, account, db):
    season(db, "summer")
    me, other = account("cutter"), account("neighbour")
    tree = summer_tree()
    stand(db, me.id, tree["x"], tree["y"] - 80)
    result = data(client.post("/trees/chop", headers=me.headers, json={"tree_id": tree["id"]}))
    assert result["wood"] == WOOD_PER_TREE == 15
    assert wood(client, me) == 15
    again = client.post("/trees/chop", headers=me.headers, json={"tree_id": tree["id"]})
    assert again.status_code == 409 and again.json()["error"] == "TREE_ALREADY_CUT"
    assert tree["id"] in data(client.get("/trees", headers=me.headers))["cut"]
    # Each player has their own map: the neighbour still has this tree.
    assert tree["id"] not in data(client.get("/trees", headers=other.headers))["cut"]
    stand(db, other.id, tree["x"], tree["y"])
    data(client.post("/trees/chop", headers=other.headers, json={"tree_id": tree["id"]}))
    assert wood(client, other) == 15


def test_chop_needs_the_player_at_the_tree_and_the_right_season(client, account, db):
    season(db, "summer")
    me = account()
    tree = summer_tree()
    stand(db, me.id, tree["x"] + GEOMETRY["tree_reach"] + 50, tree["y"])
    far = client.post("/trees/chop", headers=me.headers, json={"tree_id": tree["id"]})
    assert far.json()["error"] == "TREE_TOO_FAR"
    winter = next(t for t in GEOMETRY["trees"] if t["season"] == "winter")
    stand(db, me.id, winter["x"], winter["y"])
    wrong = client.post("/trees/chop", headers=me.headers, json={"tree_id": winter["id"]})
    assert wrong.json()["error"] == "TREE_OUT_OF_SEASON"
    unknown = client.post("/trees/chop", headers=me.headers, json={"tree_id": "Summer/NoSuchTree"})
    assert unknown.status_code == 404
    assert wood(client, me) == 0
    assert db.query(CutTree).count() == 0


def test_clearing_a_season_grows_new_trees_on_open_ground(client, account, db):
    season(db, "spring")
    me = account()
    spring = [t for t in GEOMETRY["trees"] if t["season"] == "spring"]
    # Cut all but one directly, then fell the last through the API.
    for tree in spring[:-1]:
        db.add(CutTree(player_id=me.id, tree_id=tree["id"]))
    db.commit()
    last = spring[-1]
    stand(db, me.id, last["x"], last["y"])
    house = (1000.0, -500.0)
    grown = data(client.post("/trees/chop", headers=me.headers,
                             json={"tree_id": last["id"], "avoid": [list(house)]}))["spawned"]
    assert len(grown) == REGROW_COUNT
    (fx0, fy0), (fx1, fy1) = GEOMETRY["farm"]
    for tree in grown:
        x, y = tree["x"], tree["y"]
        assert tree["season"] == "spring" and tree["scene"].startswith("res://Scenes/trees/spring/")
        assert walkable(x, y) and not at_water(x, y)
        assert not (fx0 <= x <= fx1 and fy0 <= y <= fy1), "grew on the farm"
        assert math.hypot(x - house[0], y - house[1]) >= 350, "grew on the house"
    forest = data(client.get("/trees", headers=me.headers))
    assert [t["id"] for t in forest["spawned"]] == [t["id"] for t in grown]
    # A grown tree is cut like any other, then it is gone.
    target = grown[0]
    stand(db, me.id, target["x"], target["y"])
    data(client.post("/trees/chop", headers=me.headers, json={"tree_id": target["id"]}))
    assert target["id"] not in [t["id"] for t in data(client.get("/trees", headers=me.headers))["spawned"]]
    assert wood(client, me) == 30


def test_wood_sells_to_the_store_and_trades_in_player_shops(client, account, db):
    season(db, "summer")
    seller, buyer = account("woodseller"), account("woodbuyer")
    tree = summer_tree()
    stand(db, seller.id, tree["x"], tree["y"])
    data(client.post("/trees/chop", headers=seller.headers, json={"tree_id": tree["id"]}))
    catalog = {r["item_code"]: r for r in data(client.get("/shop", headers=seller.headers))["items"]}
    assert "wood" not in catalog or catalog["wood"].get("buy_value") in (None, 0)
    data(client.post("/market", headers=seller.headers,
                     json={"option_id": "shop_option_01", "side": "left", "name": "Lumber"}))
    shop = data(client.get("/market", headers=seller.headers))["id"]
    data(client.post("/market/listings", headers=seller.headers,
                     json={"item_code": "wood", "quantity": 10, "price": 3}))
    data(client.post("/economy/earn", headers=buyer.headers, json={"amount": 100}))
    data(client.post("/market/buy", headers=buyer.headers,
                     json={"shop_id": shop, "item_code": "wood", "quantity": 4}))
    assert wood(client, buyer) == 4
    sold = client.post("/shop/sell", headers=seller.headers,
                       json={"item_code": "wood", "quantity": 5})
    assert sold.status_code == 200, sold.text
    assert wood(client, seller) == 0


def test_visitors_cannot_cut_their_hosts_trees(client, account, db, monkeypatch):
    season(db, "summer")
    me = account()
    tree = summer_tree()
    stand(db, me.id, tree["x"], tree["y"])

    class Visiting:
        is_visitor = True

    monkeypatch.setattr("app.modules.trees.service.resolve", lambda db, pid: Visiting())
    refused = client.post("/trees/chop", headers=me.headers, json={"tree_id": tree["id"]})
    assert refused.status_code == 403
    assert TreeService(db).forest(me.id)["cut"] == []


def test_owner_can_cut_in_their_private_farm(client, account, db):
    from app.modules.realtime.service import RealtimeService
    season(db, "summer")
    me = account("private_cutter")
    entered = RealtimeService(db).enter(me.id)
    assert entered["room"].startswith("world:")
    tree = summer_tree()
    stand(db, me.id, tree["x"], tree["y"] - 80)
    data(client.post("/trees/chop", headers=me.headers, json={"tree_id": tree["id"]}))
    assert wood(client, me) == WOOD_PER_TREE


def test_social_lobby_does_not_allow_private_tree_chopping(client, account, db):
    from app.modules.realtime.service import RealtimeService
    season(db, "summer")
    me = account("lobby_cutter")
    RealtimeService(db).enter(me.id, location="social_lobby")
    tree = summer_tree()
    stand(db, me.id, tree["x"], tree["y"])
    response = client.post("/trees/chop", headers=me.headers, json={"tree_id": tree["id"]})
    assert response.status_code == 403
    assert wood(client, me) == 0
