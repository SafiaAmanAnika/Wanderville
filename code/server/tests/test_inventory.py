import os
from pathlib import Path
import sys

from fastapi.testclient import TestClient

TEST_DB_PATH = Path(__file__).with_name("test_inventory.db")
if TEST_DB_PATH.exists():
    TEST_DB_PATH.unlink()
os.environ["DATABASE_URL"] = f"sqlite:///{TEST_DB_PATH.as_posix()}"
os.environ["JWT_SECRET_KEY"] = "test-secret-key"
os.environ["ACCESS_TOKEN_EXPIRE_MINUTES"] = "60"
os.environ["DISABLE_RATE_LIMIT"] = "1"

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import main as _main
from app.database import Base, engine
import app.models.player  # noqa: F401
import app.models.inventory  # noqa: F401

Base.metadata.create_all(bind=engine)

client = TestClient(_main.app)


def _signup_and_login(username="invuser", password="secret123", display_name="Inventory User"):
    client.post(
        "/auth/signup",
        json={"username": username, "password": password, "display_name": display_name},
    )
    r = client.post("/auth/login", json={"username": username, "password": password})
    return r.json()["data"]["token"]


class TestInventory:
    def test_get_inventory_empty(self):
        token = _signup_and_login("empty_inv", "secret123", "Empty")
        resp = client.get("/inventory/", headers={"Authorization": f"Bearer {token}"})
        assert resp.status_code == 200
        body = resp.json()
        assert body["success"] is True
        assert body["data"]["items"] == []
        assert body["data"]["total_items"] == 0
        assert body["data"]["total_quantity"] == 0

    def test_add_item(self):
        token = _signup_and_login("add_inv", "secret123", "Add")
        resp = client.post(
            "/inventory/add",
            headers={"Authorization": f"Bearer {token}"},
            json={"item_type": "wheat", "quantity": 5},
        )
        assert resp.status_code == 200
        body = resp.json()
        assert body["success"] is True
        assert body["data"]["quantity"] == 5
        assert body["data"]["item_type"] == "wheat"

    def test_add_item_stacks(self):
        token = _signup_and_login("stack_inv", "secret123", "Stack")
        client.post(
            "/inventory/add",
            headers={"Authorization": f"Bearer {token}"},
            json={"item_type": "wheat", "quantity": 3},
        )
        resp = client.post(
            "/inventory/add",
            headers={"Authorization": f"Bearer {token}"},
            json={"item_type": "wheat", "quantity": 2},
        )
        assert resp.json()["data"]["quantity"] == 5

    def test_remove_item(self):
        token = _signup_and_login("remove_inv", "secret123", "Remove")
        client.post(
            "/inventory/add",
            headers={"Authorization": f"Bearer {token}"},
            json={"item_type": "wheat", "quantity": 5},
        )
        resp = client.post(
            "/inventory/remove",
            headers={"Authorization": f"Bearer {token}"},
            json={"item_type": "wheat", "quantity": 2},
        )
        assert resp.status_code == 200
        assert resp.json()["data"]["quantity"] == 3

    def test_remove_item_deletes_at_zero(self):
        token = _signup_and_login("delete_inv", "secret123", "Delete")
        client.post(
            "/inventory/add",
            headers={"Authorization": f"Bearer {token}"},
            json={"item_type": "wheat", "quantity": 2},
        )
        resp = client.post(
            "/inventory/remove",
            headers={"Authorization": f"Bearer {token}"},
            json={"item_type": "wheat", "quantity": 2},
        )
        assert resp.json()["data"] is None

        resp = client.get("/inventory/", headers={"Authorization": f"Bearer {token}"})
        assert resp.json()["data"]["total_items"] == 0

    def test_remove_not_enough(self):
        token = _signup_and_login("notenough_inv", "secret123", "Not Enough")
        client.post(
            "/inventory/add",
            headers={"Authorization": f"Bearer {token}"},
            json={"item_type": "wheat", "quantity": 2},
        )
        resp = client.post(
            "/inventory/remove",
            headers={"Authorization": f"Bearer {token}"},
            json={"item_type": "wheat", "quantity": 5},
        )
        assert resp.status_code == 400

    def test_remove_not_found(self):
        token = _signup_and_login("notfound_inv", "secret123", "Not Found")
        resp = client.post(
            "/inventory/remove",
            headers={"Authorization": f"Bearer {token}"},
            json={"item_type": "corn", "quantity": 1},
        )
        assert resp.status_code == 400

    def test_multiple_item_types(self):
        token = _signup_and_login("multi_inv", "secret123", "Multi")
        client.post(
            "/inventory/add",
            headers={"Authorization": f"Bearer {token}"},
            json={"item_type": "wheat", "quantity": 3},
        )
        client.post(
            "/inventory/add",
            headers={"Authorization": f"Bearer {token}"},
            json={"item_type": "corn", "quantity": 5},
        )
        client.post(
            "/inventory/add",
            headers={"Authorization": f"Bearer {token}"},
            json={"item_type": "cotton", "quantity": 2},
        )
        resp = client.get("/inventory/", headers={"Authorization": f"Bearer {token}"})
        assert resp.status_code == 200
        body = resp.json()
        assert body["data"]["total_items"] == 3
        assert body["data"]["total_quantity"] == 10

    def test_users_have_separate_inventories(self):
        token_a = _signup_and_login("alice_inv", "secret123", "Alice")
        token_b = _signup_and_login("bob_inv", "secret123", "Bob")

        client.post(
            "/inventory/add",
            headers={"Authorization": f"Bearer {token_a}"},
            json={"item_type": "wheat", "quantity": 10},
        )

        resp_a = client.get("/inventory/", headers={"Authorization": f"Bearer {token_a}"})
        assert resp_a.json()["data"]["total_quantity"] == 10

        resp_b = client.get("/inventory/", headers={"Authorization": f"Bearer {token_b}"})
        assert resp_b.json()["data"]["total_quantity"] == 0

    def test_transfer_between_players(self):
        token_a = _signup_and_login("sender_inv", "secret123", "Sender")
        token_b = _signup_and_login("receiver_inv", "secret123", "Receiver")

        client.post(
            "/inventory/add",
            headers={"Authorization": f"Bearer {token_a}"},
            json={"item_type": "wheat", "quantity": 5},
        )

        resp = client.post(
            "/inventory/transfer",
            headers={"Authorization": f"Bearer {token_a}"},
            json={"to_player_username": "receiver_inv", "item_type": "wheat", "quantity": 3},
        )
        assert resp.status_code == 200
        assert resp.json()["success"] is True
        assert resp.json()["data"]["quantity"] == 3
        assert resp.json()["data"]["to"] == "receiver_inv"

        resp_a = client.get("/inventory/", headers={"Authorization": f"Bearer {token_a}"})
        assert resp_a.json()["data"]["items"][0]["quantity"] == 2

        resp_b = client.get("/inventory/", headers={"Authorization": f"Bearer {token_b}"})
        assert resp_b.json()["data"]["items"][0]["quantity"] == 3

    def test_get_inventory_requires_auth(self):
        resp = client.get("/inventory/")
        assert resp.status_code == 401

    def test_add_item_requires_auth(self):
        resp = client.post("/inventory/add", json={"item_type": "wheat", "quantity": 1})
        assert resp.status_code == 401

    def test_remove_item_requires_auth(self):
        resp = client.post("/inventory/remove", json={"item_type": "wheat", "quantity": 1})
        assert resp.status_code == 401
