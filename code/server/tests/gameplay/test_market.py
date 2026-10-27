"""Player shops, end to end through the routes the Godot marketplace calls."""


def data(response):
    assert response.status_code == 200, response.text
    return response.json()["data"]


def befriend(client, a, b):
    data(client.post("/social/requests", headers=a.headers, json={"target_id": b.id}))
    data(client.post(f"/social/friends/{a.id}", headers=b.headers, json={"action": "accept"}))


def quantity(client, user, code):
    items = data(client.get("/inventory/", headers=user.headers))["items"]
    return sum(i["quantity"] for i in items if i["item_code"] == code)


def aura(client, user):
    return data(client.get("/economy/", headers=user.headers))["aura_balance"]


def test_shop_stock_buy_and_sales(client, account):
    seller, buyer, stranger = account("seller"), account("buyer"), account("stranger")
    befriend(client, seller, buyer)
    assert data(client.get("/market", headers=seller.headers)) is None
    shop = data(client.post("/market", headers=seller.headers,
                            json={"option_id": "shop_option_01", "side": "left", "name": "Stall"}))
    assert client.post("/market", headers=seller.headers,
                       json={"option_id": "shop_option_01", "side": "left", "name": "Again"}).status_code == 409
    assert [s["id"] for s in data(client.get("/market/friends", headers=buyer.headers))] == [shop["id"]]
    assert data(client.get("/market/friends", headers=stranger.headers)) == []

    data(client.post("/inventory/add", headers=seller.headers, json={"item_code": "wheat", "quantity": 5}))
    data(client.post("/market/listings", headers=seller.headers,
                     json={"item_code": "wheat", "quantity": 4, "price": 7}))
    assert quantity(client, seller, "wheat") == 1
    assert client.post("/market/listings", headers=seller.headers,
                       json={"item_code": "wheat", "quantity": 4, "price": 7}).status_code != 200
    data(client.post("/market/listings/remove", headers=seller.headers,
                     json={"item_code": "wheat", "quantity": 1}))
    assert quantity(client, seller, "wheat") == 2

    data(client.post("/economy/earn", headers=buyer.headers, json={"amount": 100}))
    seller_before, buyer_before = aura(client, seller), aura(client, buyer)
    assert client.post("/market/buy", headers=seller.headers,
                       json={"shop_id": shop["id"], "item_code": "wheat", "quantity": 1}).status_code == 409
    assert client.post("/market/buy", headers=buyer.headers,
                       json={"shop_id": shop["id"], "item_code": "wheat", "quantity": 4}).status_code == 409
    data(client.post("/market/buy", headers=buyer.headers,
                     json={"shop_id": shop["id"], "item_code": "wheat", "quantity": 3}))
    assert quantity(client, buyer, "wheat") == 3
    assert aura(client, buyer) == buyer_before - 21
    assert aura(client, seller) == seller_before + 21
    assert data(client.get(f"/market/{shop['id']}/listings", headers=buyer.headers)) == []

    sales = data(client.get(f"/market/{shop['id']}/sales", headers=seller.headers))
    assert [(s["buyer_id"], s["quantity"], s["price"]) for s in sales] == [(buyer.id, 3, 7)]
    assert client.get(f"/market/{shop['id']}/sales", headers=buyer.headers).status_code == 403


def test_listing_and_buying_limits_match_the_store(client, account):
    seller = account("limits")
    data(client.post("/market", headers=seller.headers,
                     json={"option_id": "shop_option_01", "side": "right", "name": "Stall"}))
    data(client.post("/inventory/add", headers=seller.headers, json={"item_code": "wheat", "quantity": 1}))
    for body in ({"item_code": "wheat", "quantity": 1, "price": 10_000},
                 {"item_code": "wheat", "quantity": 1, "price": 10**12},
                 {"item_code": "wheat", "quantity": 100, "price": 5}):
        assert client.post("/market/listings", headers=seller.headers, json=body).status_code == 422
    assert client.post("/market/listings/remove", headers=seller.headers,
                       json={"item_code": "wheat", "quantity": 100}).status_code == 422
    assert client.post("/market/buy", headers=seller.headers,
                       json={"shop_id": 1, "item_code": "wheat", "quantity": 100}).status_code == 422
    assert quantity(client, seller, "wheat") == 1
    data(client.post("/market/listings", headers=seller.headers,
                     json={"item_code": "wheat", "quantity": 1, "price": 9999}))
