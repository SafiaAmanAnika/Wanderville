from app.modules.pets.models import PlayerPet


def test_pet_species_selection_is_persistent_and_owner_scoped(client, account, db):
    owner, other = account("pet_owner"), account("pet_other")
    for user in (owner, other):
        assert client.put("/profile", headers=user.headers, json={"character_code": "girl_a"}).status_code == 200
    for species in ("cat", "dog", "rabbit", "fox", "duck", "red_panda"):
        response = client.put("/pets", headers=owner.headers, json={"species": species})
        assert response.status_code == 200
        assert response.json()["data"]["species"] == species
        assert client.get("/pets", headers=owner.headers).json()["data"]["species"] == species
        db.expire_all()
        assert db.get(PlayerPet, other.id).species == "cat"


def test_pet_selection_rejects_unknown_species_and_missing_login(client, account):
    owner = account()
    assert client.put("/profile", headers=owner.headers, json={"character_code": "girl_a"}).status_code == 200
    assert client.put("/pets", json={"species": "dog"}).status_code == 401
    assert client.put("/pets", headers=owner.headers, json={"species": "dragon"}).status_code == 422
    assert client.get("/pets", headers=owner.headers).json()["data"]["species"] == "cat"
