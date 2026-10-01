# Manual backend checks

Complete [setup](DATABASE_SETUP.md), then open `/docs`. Use a fresh
local development database and keep `WANDERVILLE_ENV=dev` for compatibility rewards.
Do not print DATABASE_URL or raw tokens into shared logs.

1. GET `/health`: success data is `{ "status": "ok" }`.
2. POST `/auth/signup` with a new username, email and a strong password.
3. Open the development email in `code/server/.dev-mail/` and follow its
   verification link. POST `/auth/login` should return an access/refresh pair
   and public player data under `data`.
4. Use Swagger's Authorize control with the access token. GET `/auth/me`,
   `/world/me`, `/world/state`, `/inventory/`, `/economy/` and `/economy/xp`.
5. POST `/inventory/add` with `{ "item_code": "wheat", "quantity": 2 }`.
   GET `/inventory/` must return `items[0].item_code`.
6. POST `/farm/plant` with `{ "x": 3, "y": 4, "item_code": "wheat" }`.
   One inventory item is consumed; save the returned plot id.
7. POST `/farm/water` with `{ "plot_id": ID }`. Repeating immediately must
   return FARM_ALREADY_WATERED. Wait until the next stage and repeat watering
   for each of the three stage advances. Wheat takes about 12 seconds per
   watered stage in summer at the default growth rate. Dry crops pause.
8. POST `/farm/harvest` when ready. Inventory increases by one and XP is granted.
   Repeating returns FARM_EMPTY. Planting the same coordinates reuses the tile id.
9. POST `/economy/earn` and `/economy/spend` with positive amounts. Confirm
   `/economy/transactions` contains matching signed entries. Zero/negative
   amounts and XP must return 422.
10. POST `/auth/refresh` once. Reusing the old token must fail. Logout with the
    replacement refresh token; that refresh token must then fail as well.
11. Use a second account to verify inventory/world isolation and that the first
    account's plot id cannot be watered or harvested.
12. Run `python -m pytest -q` for the automated constraint and rollback checks.

For details and remaining limits, read [API_CONTRACT.md](API_CONTRACT.md)
and [BACKEND_INTEGRATION_CHECKLIST.md](BACKEND_INTEGRATION_CHECKLIST.md).
