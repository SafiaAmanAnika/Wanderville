# Manual Backend Testing Guide (Beginner Friendly)

This guide shows how to manually test the current Wanderville backend locally after you have completed setup.

All commands below are written to be copy-paste friendly for **Git Bash on Windows**.

## 1. Prerequisites

Before you begin, make sure you have:

1. Repo cloned
2. You are on the `dev` branch
3. You are inside `code/server`
4. `.venv` created and activated
5. Dependencies installed
6. `.env` created from `.env.example`
7. Database initialized with `python init_db.py`

Quick verify commands:

```bash
git status
git branch --show-current
pwd
python --version
which python
```

Expected:

1. Branch shows `dev`
2. `pwd` ends with `/code/server`
3. `which python` points inside `code/server/.venv/...`

If you still need the setup commands (run from repo root):

```bash
git checkout dev
cd code/server
python -m venv .venv
source .venv/Scripts/activate
pip install -r requirements.txt
cp .env.example .env
python init_db.py
```

## 2. Database Checks

These checks confirm SQLite is created and the expected `players` table exists.

### 2.1 Re-run init (safe)

From `code/server`:

```bash
python init_db.py
```

Expected output includes:

1. `Database initialized.`

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

## 3. Automated Test

From `code/server`:

```bash
pytest -q
```

Expected:

1. `1 passed` (the test covers signup, duplicate signup, login, wrong password, and `/auth/me` auth behavior)

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

## 6. Password Hash Check

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
5. `__pycache__/`
6. `.pytest_cache/`
