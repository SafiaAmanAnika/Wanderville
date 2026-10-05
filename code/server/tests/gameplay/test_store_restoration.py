from datetime import timedelta

import pytest
from sqlalchemy import select

from app.core.clock import utcnow
from app.modules.economy.service import EconomyService
from app.modules.farming.schemas import PlantRequest
from app.modules.farming.service import FarmingService
from app.modules.inventory.models import InventoryItem, ItemDefinition
from app.modules.inventory.schemas import ItemRequest
from app.modules.inventory.service import InventoryService
from app.modules.shop.models import ItemRule, StarterGrant, Sale
from app.modules.shop.service import ORIGINAL_SEEDS, STARTER_CODE, STARTER_ITEMS, ShopService
from app.modules.world.models import WorldState


def data(response):
    assert response.status_code == 200, response.text
    return response.json()['data']


def test_starter_pack_preserves_existing_items_and_is_never_replenished(client, account, db):
    user = account()
    inventory = InventoryService(db)
    inventory.add_compatibility(user.id, ItemRequest(item_code='wheat_seed', quantity=7))
    inventory.add_compatibility(user.id, ItemRequest(item_code='wheat', quantity=3))
    balance = EconomyService(db).get(user.id).aura_balance
    pack = data(client.post('/shop/starter/claim', headers=user.headers))
    assert pack['claimed'] and not pack['already_claimed']
    # The granted pack is two level-one all-season seeds, so the very first
    # planting always works without flooding the shared slot pool.
    assert pack['items'] == STARTER_ITEMS == {'paddy_seed': 5, 'wheat_seed': 5}
    assert inventory.repo.stack(user.id, 'wheat_seed').quantity == 12
    assert inventory.repo.stack(user.id, 'wheat').quantity == 3
    assert EconomyService(db).get(user.id).aura_balance == balance
    assert db.get(StarterGrant, (user.id, STARTER_CODE)) is not None
    catalog = {row['item_code']: row for row in data(client.get('/shop', headers=user.headers))['items']}
    assert set(STARTER_ITEMS) <= catalog.keys()
    assert all(catalog[code]['harvest_code'] == code.removesuffix('_seed') for code in STARTER_ITEMS)
    assert all(catalog[code]['required_level'] == 1 and catalog[code]['season'] == 'all' for code in STARTER_ITEMS)
    # An old account that has spent every seed must never be replenished.
    for row in inventory.repo.list(user.id):
        if row.item_code.endswith('_seed'):
            inventory.remove(user.id, ItemRequest(item_code=row.item_code, quantity=row.quantity, confirmed=True))
    for _ in range(2):
        result = data(client.post('/shop/starter/claim', headers=user.headers))
        assert result['already_claimed']
    rows = data(client.get('/inventory/', headers=user.headers))['items']
    assert [(r['item_code'], r['quantity']) for r in rows] == [('wheat', 3)]


def test_starter_grant_capacity_failure_rolls_back_whole_pack(client, account, db):
    user = account()
    # Leave exactly one free slot so the two-item pack cannot fit.
    service = InventoryService(db)
    capacity = service.capacity(user.id)
    codes = [
        code
        for code in db.scalars(select(ItemDefinition.item_code).order_by(ItemDefinition.item_code))
        if code not in STARTER_ITEMS
    ]
    for code in codes[: capacity - 1]:
        service.add_internal(user.id, code)
    db.commit()
    result = client.post('/shop/starter/claim', headers=user.headers)
    assert result.json()['error'] == 'INVENTORY_FULL'
    db.expire_all()
    assert len(
        list(db.scalars(select(InventoryItem).where(InventoryItem.player_id == user.id)))
    ) == capacity - 1
    assert db.get(StarterGrant, (user.id, STARTER_CODE)) is None
    data(client.post('/inventory/remove', headers=user.headers, json={
        'item_code': codes[0], 'quantity': 1, 'confirmed': True}))
    assert data(client.post('/shop/starter/claim', headers=user.headers))['claimed']


def test_every_recovered_seed_plants_its_own_crop_and_keeps_produce_separate(
    client, account, db, reach_level
):
    user = account()
    reach_level(user, 8)
    ShopService(db).claim_starter(user.id)
    now = utcnow()
    for crop in ORIGINAL_SEEDS:
        InventoryService(db).add_internal(user.id, crop + '_seed', 2)
    db.commit()
    for index, crop in enumerate(ORIGINAL_SEEDS):
        definition = db.scalar(select(ItemDefinition).where(ItemDefinition.item_code == crop))
        state = db.get(WorldState, 1)
        state.current_season = definition.season if definition.season != 'all' else 'summer'
        state.season_started_at = now
        db.commit()
        plot = FarmingService(db).plant(user.id, PlantRequest(x=index % 10, y=index // 10, item_code=crop + '_seed'), now).plot
        assert plot.item_code == crop
        stack = InventoryService(db).repo.stack(user.id, crop + '_seed')
        expected = (2 + STARTER_ITEMS.get(crop + '_seed', 0)) - 1
        assert (stack.quantity if stack else 0) == expected
        # Planting consumes seed only; the produce row is never created early.
        assert InventoryService(db).repo.stack(user.id, crop) is None
    result = data(client.get('/inventory/', headers=user.headers))
    assert all(row['item']['category'] == 'seed' and row['harvest_code'] in ORIGINAL_SEEDS for row in result['items'])


def test_store_receipts_are_private_and_sales_do_not_repeat_rewards(client, account, db):
    user, other = account(), account('receipt_other')
    InventoryService(db).add_compatibility(user.id, ItemRequest(item_code='wheat', quantity=4))
    before = EconomyService(db).get(user.id).aura_balance
    sale = {'request_id': 'sale_replay_01', 'item_code': 'wheat', 'quantity': 2}
    first = data(client.post('/shop/sell', headers=user.headers, json=sale))
    xp = EconomyService(db).xp(user.id).total_xp
    assert data(client.post('/shop/sell', headers=user.headers, json=sale)) == first
    assert InventoryService(db).repo.stack(user.id, 'wheat').quantity == 2
    assert EconomyService(db).get(user.id).aura_balance == before + 24
    assert EconomyService(db).xp(user.id).total_xp == xp
    receipt = data(client.get('/shop/transactions/sale_replay_01?action=sell', headers=user.headers))
    assert receipt['found'] and receipt['receipt']['quantity'] == 2
    assert not data(client.get('/shop/transactions/sale_replay_01?action=sell', headers=other.headers))['found']
    assert client.post('/shop/sell', headers=user.headers, json={**sale, 'quantity': 1}).status_code == 409
    buy = {'request_id': 'buy_replay_01', 'item_code': 'wheat_seed', 'quantity': 2}
    data(client.post('/shop/buy', headers=user.headers, json=buy))
    after = EconomyService(db).get(user.id).aura_balance
    data(client.post('/shop/buy', headers=user.headers, json=buy))
    assert EconomyService(db).get(user.id).aura_balance == after
    assert InventoryService(db).repo.stack(user.id, 'wheat_seed').quantity == 2
    assert data(client.get('/shop/transactions/buy_replay_01', headers=user.headers))['found']
    assert client.get('/shop/transactions/buy_replay_01').status_code == 401


@pytest.mark.parametrize('reason', ['funds', 'level', 'stack', 'stock'])
def test_purchase_rejections_are_atomic(client, account, db, monkeypatch, reason):
    user = account()
    code = 'wheat_seed'
    if reason == 'level':
        db.get(ItemRule, code).required_level = 9
        db.commit()
    elif reason == 'stack':
        # A full stack is no longer a ceiling: the purchase is only refused
        # when every slot in the shared pool is occupied.
        inventory = InventoryService(db)
        inventory.add_compatibility(user.id, ItemRequest(item_code=code, quantity=99))
        codes = [
            item
            for item in db.scalars(
                select(ItemDefinition.item_code).order_by(ItemDefinition.item_code)
            )
            if item != code
        ]
        for item in codes[: inventory.capacity(user.id) - 1]:
            inventory.add_internal(user.id, item)
        db.commit()
        assert inventory.list(user.id).used_slots == inventory.capacity(user.id)
    elif reason == 'stock':
        monkeypatch.setattr(ShopService, 'available', lambda *_: False)
    quantity = 99 if reason == 'funds' else 1
    before = EconomyService(db).get(user.id).aura_balance
    rows_before = [(r.item_code, r.quantity) for r in InventoryService(db).repo.list(user.id)]
    response = client.post('/shop/buy', headers=user.headers, json={'request_id': 'rejected_purchase', 'item_code': code, 'quantity': quantity})
    assert response.status_code == 400
    assert response.json()['error'] == {'funds': 'INSUFFICIENT_FUNDS', 'level': 'LEVEL_LOCKED', 'stack': 'INVENTORY_FULL', 'stock': 'OUT_OF_STOCK'}[reason]
    db.expire_all()
    assert EconomyService(db).get(user.id).aura_balance == before
    assert [(r.item_code, r.quantity) for r in InventoryService(db).repo.list(user.id)] == rows_before
    assert not data(client.get('/shop/transactions/rejected_purchase', headers=user.headers))['found']


def test_seed_restrictions_do_not_consume_inventory(client, account, db, reach_level):
    user = account()
    ShopService(db).claim_starter(user.id)
    InventoryService(db).add_compatibility(user.id, ItemRequest(item_code='potato_seed', quantity=2))
    rule = db.get(ItemRule, 'wheat_seed')
    rule.required_level = 4
    db.commit()
    rows = data(client.get('/inventory/', headers=user.headers))['items']
    assert next(r for r in rows if r['item_code'] == 'wheat_seed')['required_level'] == 4
    assert client.post('/farm/plant', headers=user.headers, json={'x': 0, 'y': 0, 'item_code': 'wheat_seed'}).json()['error'] == 'LEVEL_LOCKED'
    # Season is only judged once the level lock is satisfied.
    reach_level(user, 4)
    state = db.get(WorldState, 1)
    state.current_season = 'summer'
    state.season_started_at = utcnow() - timedelta(seconds=1)
    db.commit()
    assert client.post('/farm/plant', headers=user.headers, json={'x': 0, 'y': 0, 'item_code': 'potato_seed'}).json()['error'] == 'OUT_OF_SEASON'
    # Neither refused attempt consumed a seed.
    assert InventoryService(db).repo.stack(user.id, 'wheat_seed').quantity == 5
    assert InventoryService(db).repo.stack(user.id, 'potato_seed').quantity == 2


def test_sale_failure_does_not_create_receipt(client, account, db):
    user = account()
    result = client.post('/shop/sell', headers=user.headers, json={'request_id': 'empty_sale_01', 'item_code': 'wheat', 'quantity': 1})
    assert result.json()['error'] == 'INSUFFICIENT_INVENTORY'
    assert db.get(Sale, (user.id, 'empty_sale_01')) is None


def test_sales_pay_per_produce_unit_but_never_seed_resales(client, account, db):
    bulk, split = account('bulk_seller'), account('split_seller')
    for user in (bulk, split):
        InventoryService(db).add_compatibility(user.id, ItemRequest(item_code='wheat', quantity=20))
    data(client.post('/shop/sell', headers=bulk.headers, json={
        'request_id': 'bulk_produce_sale', 'item_code': 'wheat', 'quantity': 20}))
    for index in range(4):
        data(client.post('/shop/sell', headers=split.headers, json={
            'request_id': f'split_produce_{index}', 'item_code': 'wheat', 'quantity': 5}))
    for user in (bulk, split):
        xp = data(client.get('/economy/xp', headers=user.headers))
        assert xp['total_xp'] == 100 and xp['level'] == 2
        assert data(client.get('/economy/', headers=user.headers))['aura_balance'] == 10 + 240 + 25
        purchase = {'request_id': 'resale_seeds_buy', 'item_code': 'wheat_seed', 'quantity': 2}
        data(client.post('/shop/buy', headers=user.headers, json=purchase))
        sale = {'request_id': 'resale_seeds_sell', 'item_code': 'wheat_seed', 'quantity': 2}
        data(client.post('/shop/sell', headers=user.headers, json=sale))
        data(client.post('/shop/sell', headers=user.headers, json=sale))
        assert data(client.get('/economy/xp', headers=user.headers))['total_xp'] == 100
