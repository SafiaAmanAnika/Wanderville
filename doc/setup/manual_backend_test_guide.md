# Manual Backend Testing Guide

This guide shows how to manually test the current Wanderville backend locally after you have completed setup.

All commands below are written for **PowerShell on Windows**.

## 1. Prerequisites

Before you begin, make sure you have:

1. Repo cloned
2. You are inside `code/server`
3. `.venv` created and activated
4. Dependencies installed (including alembic)
5. `.env` created from `.env.example`
6. Database created via `python -m alembic upgrade head`

Quick verify commands:

```powershell
pwd
python --version
(Get-Command python).Source
```

Expected:

1. `pwd` ends with `code\server`
2. `python` points inside `code\server\.venv\...`

If you still need the setup commands (run from repo root):

```powershell
cd code/server
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
cp .env.example .env
python -m alembic upgrade head
```

## 2. Database Checks

These checks confirm SQLite is created and the expected `players` table exists.

### 2.1 Verify migrations are applied

From `code/server`:

```powershell
python -m alembic upgrade head
```

Expected output includes:

1. `INFO [alembic.runtime.migration] Running upgrade ...`

### 2.2 Check that `wanderville.db` exists

```powershell
Test-Path wanderville.db
```

Expected:

1. Returns `True`

### 2.3 Check that `players` table exists (via sqlite3 through Python)

Run this exact one-liner:

```powershell
python -c "import sqlite3; con=sqlite3.connect('wanderville.db'); cur=con.cursor(); cur.execute(\"SELECT name FROM sqlite_master WHERE type='table' ORDER BY name\"); print([r[0] for r in cur.fetchall()]); con.close()"
```

Expected:

1. You see `players` in the printed list.

### 2.4 Check `players` table columns

```powershell
python -c "import sqlite3; con=sqlite3.connect('wanderville.db'); cur=con.cursor(); cur.execute('PRAGMA table_info(players)'); print(cur.fetchall()); con.close()"
```

Expected columns (names may appear in a tuple list):

1. `id`
2. `username`
3. `hashed_password`
4. `display_name`
5. `created_at`
6. `is_active`
7. `position_x`
8. `position_y`

## 3. Automated Test

From `code/server`:

```powershell
python -m pytest -q
```

Expected:

1. `41 passed` (covers auth, world, and inventory endpoints)

## 4. Start Server

From `code/server`:

```powershell
$env:DISABLE_RATE_LIMIT=1  # optional: disable rate limiting
uvicorn main:app --reload
```

Expected:

1. Uvicorn logs showing it is running
2. Server available at `http://127.0.0.1:8000`

Keep this terminal running. Open a second PowerShell terminal for the curl commands below.

## 5. Manual API Checks

Base URL used below:

```powershell
$BASE_URL = "http://127.0.0.1:8000"
```

Pick a username/password for testing:

```powershell
$USERNAME = "manualtester"
$PASSWORD = "secret123"
$DISPLAY_NAME = "Manual Tester"
```

Tip: if you see `USERNAME_TAKEN`, change `$USERNAME` and try again.

### 5.1 GET `/health`

```powershell
curl.exe -sS "$BASE_URL/health"
```

Expected:

1. `{"success":true,"data":{"status":"ok"}}`

### 5.2 POST `/auth/signup`

```powershell
curl.exe -sS -X POST "$BASE_URL/auth/signup" `
  -H "Content-Type: application/json" `
  -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\",\"display_name\":\"$DISPLAY_NAME\"}"
```

Expected:

1. `success: true`
2. Returned player data includes `username` and `display_name`
3. Returned player data should NOT include `hashed_password`

### 5.3 Duplicate signup (same username again)

Run the same signup command again:

```powershell
curl.exe -sS -X POST "$BASE_URL/auth/signup" `
  -H "Content-Type: application/json" `
  -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\",\"display_name\":\"$DISPLAY_NAME\"}"
```

Expected:

1. `success: false`
2. `error: "USERNAME_TAKEN"`

### 5.4 POST `/auth/login`

```powershell
curl.exe -sS -X POST "$BASE_URL/auth/login" `
  -H "Content-Type: application/json" `
  -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}"
```

Expected:

1. `success: true`
2. `data.token` is a non-empty string
3. `data.player` contains the current player

### 5.5 Wrong password login

```powershell
curl.exe -sS -X POST "$BASE_URL/auth/login" `
  -H "Content-Type: application/json" `
  -d "{\"username\":\"$USERNAME\",\"password\":\"wrongpass\"}"
```

Expected:

1. `success: false`
2. `error: "INVALID_CREDENTIALS"`

### 5.6 GET `/auth/me` without token

```powershell
curl.exe -sS "$BASE_URL/auth/me"
```

Expected:

1. `success: false`
2. `error: "NOT_AUTHENTICATED"`

### 5.7 Save token from login

Re-run login, and save the token into an environment variable.

```powershell
$TOKEN = (curl.exe -sS -X POST "$BASE_URL/auth/login" `
  -H "Content-Type: application/json" `
  -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}" | python -c "import sys, json; print(json.load(sys.stdin)['data']['token'])")
echo $TOKEN
```

Expected:

1. A long token string prints

### 5.8 GET `/auth/me` with token

```powershell
curl.exe -sS "$BASE_URL/auth/me" `
  -H "Authorization: Bearer $TOKEN"
```

Expected:

1. `success: true`
2. Returned player data matches your logged-in user (`username` is `$USERNAME`)
3. Returned player data includes `position_x` and `position_y` (both default to `0`)

### 5.9 Verify position fields in player data

After logging in and getting your token (step 5.7), check that the player response includes position fields:

```powershell
curl.exe -sS "$BASE_URL/auth/me" `
  -H "Authorization: Bearer $TOKEN" `
  | python -c "import sys, json; d=json.load(sys.stdin)['data']; print(f'position_x={d[\"position_x\"]}, position_y={d[\"position_y\"]}')"
```

Expected:

1. `position_x=0, position_y=0` (new players start at origin)

## 6. Testing OAuth2 Authentication

This section verifies that the new `OAuth2PasswordBearer` token extraction works correctly.

### 6.1 Missing Authorization header returns 401

```powershell
curl.exe -sS -w "`nHTTP_CODE:%{http_code}`n" "$BASE_URL/auth/me"
```

Expected:

1. HTTP status code `401`
2. Response includes `"success": false`
3. Error code is `"NOT_AUTHENTICATED"`

### 6.2 Malformed Authorization header returns 401

```powershell
curl.exe -sS -w "`nHTTP_CODE:%{http_code}`n" "$BASE_URL/auth/me" `
  -H "Authorization: InvalidFormat"
```

Expected:

1. HTTP status code `401`
2. Response includes `"success": false`
3. Error code is `"NOT_AUTHENTICATED"`

### 6.3 Expired or invalid token returns 401

```powershell
curl.exe -sS -w "`nHTTP_CODE:%{http_code}`n" "$BASE_URL/auth/me" `
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.invalid"
```

Expected:

1. HTTP status code `401`
2. Response includes `"success": false`
3. Error code is `"INVALID_TOKEN"`

### 6.4 Valid token returns player data with position fields

Use the token from step 5.7:

```powershell
curl.exe -sS "$BASE_URL/auth/me" `
  -H "Authorization: Bearer $TOKEN" `
  | python -m json.tool
```

Expected:

1. HTTP status code `200`
2. `"success": true`
3. `data` contains `id`, `username`, `display_name`, `created_at`, `is_active`, `position_x`, `position_y`
4. `position_x` and `position_y` are integers (default `0`)

### 6.5 OpenAPI docs show auth scheme

Open `http://127.0.0.1:8000/docs` in a browser.

Expected:

1. All endpoints show lock icons where authentication is required
2. Click "Authorize" button at the top — you can paste your Bearer token there
3. The token URL for auth is listed as `/auth/login`

## 7. Password Hash Check

This confirms the backend stores a password hash in SQLite, not the plain password.

### 7.1 Query `username` and `hashed_password` from `players`

From `code/server`:

```powershell
python -c "import os, sqlite3; u='manualtester'; con=sqlite3.connect('wanderville.db'); cur=con.cursor(); cur.execute('SELECT username, hashed_password FROM players WHERE username=?', (u,)); print(cur.fetchone()); con.close()"
```

Expected:

1. The result is something like `('yourname', '$2b$...')`
2. `hashed_password` should NOT equal the password you typed

## 8. Expected Results (Summary)

1. `GET /health` returns `success: true`
2. `POST /auth/signup` returns `success: true`
3. Duplicate signup returns `error: "USERNAME_TAKEN"`
4. `POST /auth/login` returns a `token`
5. Wrong password returns `error: "INVALID_CREDENTIALS"`
6. `GET /auth/me` without token returns `error: "NOT_AUTHENTICATED"`
7. `GET /auth/me` with token returns the current player
8. Password in database looks like a bcrypt hash (often starts with something like `$2b$`) and is not the original password
9. World auto-created on signup available via `GET /world/me`
10. Farm crops can be planted, watered, and harvested
11. Inventory items can be added, removed, and transferred between players

## 9. Troubleshooting

### `ModuleNotFoundError`

Meaning:

1. Dependencies are not installed, or
2. Your `.venv` is not activated

Fix (from `code/server`):

```powershell
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

### `.env` missing

Fix (from `code/server`):

```powershell
Copy-Item .env.example .env
python -m alembic upgrade head
```

### `USERNAME_TAKEN`

Meaning:

1. You already created that username in your local database

Fix:

1. Use a new username (recommended)

### Port `8000` already in use

Meaning:

1. Another server process is already using port 8000

Fix:

1. Stop the old `uvicorn` terminal, or
2. Run in another terminal and pick another port:

```powershell
uvicorn main:app --reload --port 8001
```

### bcrypt warning

If you see warnings/errors related to bcrypt versions:

1. Use the pinned version in `requirements.txt`
2. Reinstall from requirements to match the repo:

```powershell
pip install -r requirements.txt
```

## 10. What Not To Commit

Do not commit these local-only files/folders:

1. `.env`
2. `.venv/`
3. `wanderville.db`
4. `test_*.db` (all test databases)
5. `__pycache__/`
6. `.pytest_cache/`

## 11. Testing World Endpoints

### Prerequisites

Make sure you have:

1. Applied the latest migration: `python -m alembic upgrade head`
2. A valid token from the login step (see section 5.7)

### 11.1 GET `/world/me`

Returns the current player's world. If no world exists, one is auto-created.

```powershell
curl.exe -sS "$BASE_URL/world/me" `
  -H "Authorization: Bearer $TOKEN"
```

Expected:

1. `success: true`
2. `data.id` is an integer
3. `data.owner_id` matches your player ID
4. `data.name` defaults to `"My World"`
5. `data.tiles` is an empty object `{}` for a new world
6. `data.created_at` is an ISO timestamp

### 11.2 PUT `/world/tiles`

Replace the entire tiles dictionary for your world.

```powershell
curl.exe -sS -X PUT "$BASE_URL/world/tiles" `
  -H "Authorization: Bearer $TOKEN" `
  -H "Content-Type: application/json" `
  -d '{\"tiles\": {\"0,0\": \"grass\", \"1,0\": \"dirt\", \"0,1\": \"water\"}}'
```

Expected:

1. `success: true`
2. `data.tiles` now contains `{"0,0": "grass", "1,0": "dirt", "0,1": "water"}`
3. `message: "Tiles updated"`

### 11.3 PUT `/world/tile`

Set a single tile at a specific coordinate.

```powershell
curl.exe -sS -X PUT "$BASE_URL/world/tile" `
  -H "Authorization: Bearer $TOKEN" `
  -H "Content-Type: application/json" `
  -d '{\"x\": 2, \"y\": 3, \"tile_type\": \"stone\"}'
```

Expected:

1. `success: true`
2. `data.tiles` now includes `"2,3": "stone"` alongside any existing tiles
3. `message: "Tile updated"`

### 11.4 Verify tiles with `/world/me`

After updating tiles, confirm they persisted:

```powershell
curl.exe -sS "$BASE_URL/world/me" `
  -H "Authorization: Bearer $TOKEN" `
  | python -m json.tool
```

Expected:

1. `data.tiles` contains all tiles you set in previous steps

### 11.5 Unauthorized access (no token)

```powershell
curl.exe -sS -w "`nHTTP_CODE:%{http_code}`n" "$BASE_URL/world/me"
```

Expected:

1. HTTP status code `401`
2. `success: false`
3. `error: "NOT_AUTHENTICATED"`

## 12. Testing Farm Endpoints

### Prerequisites

Make sure you have:

1. A valid token from the login step (see section 5.7)

### 12.1 GET `/farm/plots`

Returns all active farm plots for the current player.

```powershell
curl.exe -sS "$BASE_URL/farm/plots" `
  -H "Authorization: Bearer $TOKEN"
```

Expected:

1. `success: true`
2. `data.plots` is an empty array `[]` for a new player
3. `data.player_id` matches your player ID

### 12.2 POST `/farm/plant`

Plant a crop at grid coordinates (x, y).

```powershell
curl.exe -sS -X POST "$BASE_URL/farm/plant" `
  -H "Authorization: Bearer $TOKEN" `
  -H "Content-Type: application/json" `
  -d '{\"x\": 0, \"y\": 0, \"crop_type\": \"wheat\"}'
```

Expected:

1. `success: true`
2. `data.plot.crop_type` is `"wheat"`
3. `data.plot.growth_stage` is `0`
4. `data.plot.is_watered` is `false`
5. `data.water_remaining` is `50`

### 12.3 POST `/farm/water`

Water a specific plot by its ID.

```powershell
curl.exe -sS -X POST "$BASE_URL/farm/water" `
  -H "Authorization: Bearer $TOKEN" `
  -H "Content-Type: application/json" `
  -d '{\"plot_id\": 1}'
```

Expected:

1. `success: true`
2. `data.is_watered` is `true`
3. `message: "Plot 1 watered"`

### 12.4 POST `/farm/harvest`

Harvest a plot when it is fully grown.

Note: crops progress through 3 growth stages based on elapsed time and watering. Use the scheduler or wait for growth before harvesting.

```powershell
curl.exe -sS -X POST "$BASE_URL/farm/harvest" `
  -H "Authorization: Bearer $TOKEN" `
  -H "Content-Type: application/json" `
  -d '{\"plot_id\": 1}'
```

Expected (when plot is ready):

1. `success: true`
2. `data.crop_type` matches the planted crop
3. `data.quantity` is `1`

### 12.5 Duplicate plant at same coordinates

```powershell
curl.exe -sS -X POST "$BASE_URL/farm/plant" `
  -H "Authorization: Bearer $TOKEN" `
  -H "Content-Type: application/json" `
  -d '{\"x\": 0, \"y\": 0, \"crop_type\": \"corn\"}'
```

Expected:

1. HTTP status code `400`
2. Error message indicates the plot is already occupied

## 13. Testing Inventory Endpoints

### Prerequisites

Make sure you have:

1. A valid token from the login step (see section 5.7)

### 13.1 GET `/inventory/`

Returns all items in the player's inventory.

```powershell
curl.exe -sS "$BASE_URL/inventory/" `
  -H "Authorization: Bearer $TOKEN"
```

Expected:

1. `success: true`
2. `data.items` is an empty array `[]` for a new player
3. `data.total_items` is `0`
4. `data.total_quantity` is `0`

### 13.2 POST `/inventory/add`

Add items to the player's inventory.

```powershell
curl.exe -sS -X POST "$BASE_URL/inventory/add" `
  -H "Authorization: Bearer $TOKEN" `
  -H "Content-Type: application/json" `
  -d '{\"item_type\": \"wheat\", \"quantity\": 5}'
```

Expected:

1. `success: true`
2. `data.item_type` is `"wheat"`
3. `data.quantity` is `5`

### 13.3 Add the same item again (stacks)

```powershell
curl.exe -sS -X POST "$BASE_URL/inventory/add" `
  -H "Authorization: Bearer $TOKEN" `
  -H "Content-Type: application/json" `
  -d '{\"item_type\": \"wheat\", \"quantity\": 3}'
```

Expected:

1. `success: true`
2. `data.quantity` is `8` (5 + 3)

### 13.4 POST `/inventory/remove`

Remove items from inventory.

```powershell
curl.exe -sS -X POST "$BASE_URL/inventory/remove" `
  -H "Authorization: Bearer $TOKEN" `
  -H "Content-Type: application/json" `
  -d '{\"item_type\": \"wheat\", \"quantity\": 2}'
```

Expected:

1. `success: true`
2. `data.quantity` is `6` (8 - 2)

### 13.5 POST `/inventory/transfer`

Transfer items to another player.

First create a second user and get their token, then:

```powershell
# Using the first player's token
curl.exe -sS -X POST "$BASE_URL/inventory/transfer" `
  -H "Authorization: Bearer $TOKEN" `
  -H "Content-Type: application/json" `
  -d '{\"to_player_username\": \"otherplayer\", \"item_type\": \"wheat\", \"quantity\": 2}'
```

Expected:

1. `success: true`
2. `data.quantity` is `2`
3. `data.to` is `"otherplayer"`
4. `message: "Sent 2 wheat to otherplayer"`
