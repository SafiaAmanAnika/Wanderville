# Manual Backend Testing Guide

This guide shows how to manually test the current Wanderville backend locally after you have completed setup.

All commands below are written to be copy-paste friendly for **Git Bash on Windows**.

## 1. Prerequisites

Before you begin, make sure you have:

1. Repo cloned
2. You are on the `authentication-and-database` branch
3. You are inside `code/server`
4. `.venv` created and activated
5. Dependencies installed (including alembic)
6. `.env` created from `.env.example`
7. Database created via `python -m alembic upgrade head`

Quick verify commands:

```bash
git status
git branch --show-current
pwd
python --version
which python
```

Expected:

1. Branch shows `authentication-and-database`
2. `pwd` ends with `/code/server`
3. `which python` points inside `code/server/.venv/...`

If you still need the setup commands (run from repo root):

```bash
git checkout authentication-and-database
cd code/server
python -m venv .venv
source .venv/Scripts/activate
pip install -r requirements.txt
cp .env.example .env
python -m alembic upgrade head
```

## 2. Database Checks

These checks confirm SQLite is created and the expected `players` table exists.

### 2.1 Verify migrations are applied

From `code/server`:

```bash
python -m alembic upgrade head
```

Expected output includes:

1. `INFO [alembic.runtime.migration] Running upgrade ...`

### 2.2 Check that `wanderville.db` exists

```bash
ls -la wanderville.db
```

Expected:

1. The file exists in `code/server`.

### 2.3 Check that `players` table exists (via sqlite3 through Python)

Run this exact one-liner:

```bash
python -c "import sqlite3; con=sqlite3.connect('wanderville.db'); cur=con.cursor(); cur.execute(\"SELECT name FROM sqlite_master WHERE type='table' ORDER BY name\"); print([r[0] for r in cur.fetchall()]); con.close()"
```

Expected:

1. You see `players` in the printed list.

### 2.4 Check `players` table columns

```bash
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

```bash
python -m pytest -q
```

Expected:

1. `2 passed` (test_auth.py covers signup/login/me flow; test_auth_deps.py covers OAuth2 token handling and position fields)

## 4. Start Server

From `code/server`:

```bash
uvicorn main:app --reload
```

Expected:

1. Uvicorn logs showing it is running
2. Server available at `http://127.0.0.1:8000`

Keep this terminal running. Open a second Git Bash terminal for the curl commands below.

## 5. Manual API Checks With curl

Base URL used below:

```bash
BASE_URL="http://127.0.0.1:8000"
```

Pick a username/password for testing:

```bash
USERNAME="manualtester"
PASSWORD="secret123"
DISPLAY_NAME="Manual Tester"
```

Tip: if you see `USERNAME_TAKEN`, change `USERNAME` and try again.

### 5.1 GET `/health`

```bash
curl -sS "$BASE_URL/health"
```

Expected:

1. `{"success":true,"data":{"status":"ok"}}` (formatting may differ)

### 5.2 POST `/auth/signup`

```bash
curl -sS -X POST "$BASE_URL/auth/signup" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\",\"display_name\":\"$DISPLAY_NAME\"}"
```

Expected:

1. `success: true`
2. Returned player data includes `username` and `display_name`
3. Returned player data should NOT include `hashed_password`

### 5.3 Duplicate signup (same username again)

Run the same signup command again:

```bash
curl -sS -X POST "$BASE_URL/auth/signup" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\",\"display_name\":\"$DISPLAY_NAME\"}"
```

Expected:

1. `success: false`
2. `error: "USERNAME_TAKEN"`

### 5.4 POST `/auth/login`

```bash
curl -sS -X POST "$BASE_URL/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}"
```

Expected:

1. `success: true`
2. `data.token` is a non-empty string
3. `data.player` contains the current player

### 5.5 Wrong password login

```bash
curl -sS -X POST "$BASE_URL/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USERNAME\",\"password\":\"wrongpass\"}"
```

Expected:

1. `success: false`
2. `error: "INVALID_CREDENTIALS"`

### 5.6 GET `/auth/me` without token

```bash
curl -sS "$BASE_URL/auth/me"
```

Expected:

1. `success: false`
2. `error: "NOT_AUTHENTICATED"`

### 5.7 Save token from login

Re-run login, and save the token into an environment variable.

This uses Python to parse JSON reliably (works in Git Bash):

```bash
TOKEN=$(curl -sS -X POST "$BASE_URL/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}" \
  | python -c "import sys, json; print(json.load(sys.stdin)['data']['token'])")
echo "$TOKEN"
```

Expected:

1. A long token string prints

### 5.8 GET `/auth/me` with token

```bash
curl -sS "$BASE_URL/auth/me" \
  -H "Authorization: Bearer $TOKEN"
```

Expected:

1. `success: true`
2. Returned player data matches your logged-in user (`username` is `$USERNAME`)
3. Returned player data includes `position_x` and `position_y` (both default to `0`)

## 5.9 Verify position fields in player data

After logging in and getting your token (step 5.7), check that the player response includes position fields:

```bash
curl -sS "$BASE_URL/auth/me" \
  -H "Authorization: Bearer $TOKEN" \
  | python -c "import sys, json; d=json.load(sys.stdin)['data']; print(f'position_x={d[\"position_x\"]}, position_y={d[\"position_y\"]}')"
```

Expected:

1. `position_x=0, position_y=0` (new players start at origin)

## 6. Testing OAuth2 Authentication

This section verifies that the new `OAuth2PasswordBearer` token extraction works correctly.

### 6.1 Missing Authorization header returns 401

```bash
curl -sS -w "\nHTTP_CODE:%{http_code}\n" "$BASE_URL/auth/me"
```

Expected:

1. HTTP status code `401`
2. Response includes `"success": false`
3. Error code is `"NOT_AUTHENTICATED"`

### 6.2 Malformed Authorization header returns 401

```bash
curl -sS -w "\nHTTP_CODE:%{http_code}\n" "$BASE_URL/auth/me" \
  -H "Authorization: InvalidFormat"
```

Expected:

1. HTTP status code `401`
2. Response includes `"success": false`
3. Error code is `"NOT_AUTHENTICATED"`

### 6.3 Expired or invalid token returns 401

```bash
curl -sS -w "\nHTTP_CODE:%{http_code}\n" "$BASE_URL/auth/me" \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.invalid"
```

Expected:

1. HTTP status code `401`
2. Response includes `"success": false`
3. Error code is `"INVALID_TOKEN"`

### 6.4 Valid token returns player data with position fields

Use the token from step 5.7:

```bash
curl -sS "$BASE_URL/auth/me" \
  -H "Authorization: Bearer $TOKEN" \
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

1. `/auth/me` endpoint shows a lock icon (requires authentication)
2. Click "Authorize" button at the top — you can paste your Bearer token there
3. The token URL for auth is listed as `/auth/login`

## 7. Password Hash Check

This confirms the backend stores a password hash in SQLite, not the plain password.

### 6.1 Query `username` and `hashed_password` from `players`

From `code/server`:

```bash
python -c "import os, sqlite3; u=os.environ.get('USERNAME','manualtester'); con=sqlite3.connect('wanderville.db'); cur=con.cursor(); cur.execute('SELECT username, hashed_password FROM players WHERE username=?', (u,)); print(cur.fetchone()); con.close()"
```

This uses your `$USERNAME` shell variable (or falls back to `manualtester` if not set).

Expected:

1. The result is something like `('yourname', '$2b$...')`
2. `hashed_password` should NOT equal the password you typed

## 7. Expected Results (Summary)

1. `GET /health` returns `success: true`
2. `POST /auth/signup` returns `success: true`
3. Duplicate signup returns `error: "USERNAME_TAKEN"`
4. `POST /auth/login` returns a `token`
5. Wrong password returns `error: "INVALID_CREDENTIALS"`
6. `GET /auth/me` without token returns `error: "NOT_AUTHENTICATED"`
7. `GET /auth/me` with token returns the current player
8. Password in database looks like a bcrypt hash (often starts with something like `$2b$`) and is not the original password

## 8. Troubleshooting

### `ModuleNotFoundError`

Meaning:

1. Dependencies are not installed, or
2. Your `.venv` is not activated

Fix (from `code/server`):

```bash
source .venv/Scripts/activate
pip install -r requirements.txt
```

### `.env` missing

Fix (from `code/server`):

```bash
cp .env.example .env
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

```bash
uvicorn main:app --reload --port 8001
```

### bcrypt warning

If you see warnings/errors related to bcrypt versions:

1. Use the pinned version in `requirements.txt`
2. Reinstall from requirements to match the repo:

```bash
pip install -r requirements.txt
```

## 9. What Not To Commit

Do not commit these local-only files/folders:

1. `.env`
2. `.venv/`
3. `wanderville.db`
4. `tests/test_auth.db`
5. `tests/test_auth_deps.db`
6. `__pycache__/`
7. `.pytest_cache/`
