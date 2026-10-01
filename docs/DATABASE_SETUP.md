# Backend and database setup

Use Python 3.12 (the validated runtime) and a local PostgreSQL installation. The
new migration chain is intended for a fresh database. An old database at
`005_add_auth_upgrade` cannot be upgraded with this baseline. Do not stamp it as
current. See [the reset guide](database/RESET.md).

## First local PostgreSQL setup

Open `psql -U postgres -d postgres` and run:

```sql
CREATE ROLE wanderville_app LOGIN;
\password wanderville_app
CREATE DATABASE wanderville_dev OWNER wanderville_app;
```

The password prompt keeps credentials out of shell history. The role owns this
development database, permitting migrations; a production setup can use a
separate migration owner and a restricted runtime role.

## Windows PowerShell

From the project root:

```powershell
cd code/server
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements-dev.txt
if (!(Test-Path .env)) { Copy-Item .env.example .env }
python -c "import secrets; print(secrets.token_urlsafe(48))"
```

Edit `.env`: set the generated JWT secret and the password/port for your **new
local development** database. URL-encode special characters in the database
password. Use `postgresql+psycopg2://...`; never commit `.env`.
Keep an existing `.env` when returning to this project; the conditional copy
above creates it only when missing. Reuse the existing virtual environment if
it already uses Python 3.12.

```powershell
python -m alembic upgrade head
python -m app.db.seed
python -m alembic check
python -m alembic current
python -m pytest -q
python -m uvicorn main:app --reload --no-access-log
```

For a shell without the Windows `py` launcher, use `python -m venv .venv` after
selecting Python 3.12. On Linux/macOS activate with `source .venv/bin/activate`.
For runtime-only installation use `requirements.txt`; tests additionally require
`requirements-dev.txt`.

Open `http://127.0.0.1:8000/docs` or `/health`. `python -m app` is an alternate
entrypoint that honors WANDERVILLE_HOST and WANDERVILLE_PORT. The ordinary Uvicorn
CLI accepts its own `--host` and `--port` options.

There is no automatic migration, `create_all`, database reset, or catalog seed on
application startup or in `get_db()`. Seed explicitly before gameplay requests.
See [manual backend checks](MANUAL_BACKEND_TEST_GUIDE.md) for an API walkthrough.

## Local account verification

In dev/test, signup writes an email into `code/server/.dev-mail/`. Open the newest
`.eml` privately and follow its verification link. No actual email is sent and
tokens are not printed in logs. Tests replace the delivery function entirely.

The reset email includes a `wanderville://reset-password?token=...` URI and the
POST API instructions. The operating-system protocol handler still needs a
packaged client setup; this refactor does not install it. For local manual testing
use `/docs` and send the token with `new_password` to POST `/auth/reset-password`.

## PostgreSQL integration tests

Create a **separate disposable** database using `psql -U postgres -d postgres`:

```sql
CREATE DATABASE wanderville_test OWNER wanderville_app;
```

Then, from `code/server`, in PowerShell:

```powershell
$env:WANDERVILLE_TEST_DATABASE_URL = 'postgresql+psycopg2://wanderville_app:YOUR_LOCAL_PASSWORD@127.0.0.1:5432/wanderville_test'
$env:WANDERVILLE_ALLOW_TEST_RESET = '1'
python -m pytest -q
Remove-Item Env:WANDERVILLE_TEST_DATABASE_URL
Remove-Item Env:WANDERVILLE_ALLOW_TEST_RESET
```

Tests refuse PostgreSQL URLs whose database name does not end in `_test`, and
require the reset flag. This suite rebuilds/clears that test database. It never
uses the application's DATABASE_URL. With neither variable set, tests use a
temporary SQLite file with foreign keys enabled and skip PostgreSQL concurrency
tests. Run against an empty test database for the first baseline application.

## Deployment configuration

Use `WANDERVILLE_ENV=production`, a random secret, explicit CORS origins, a
PostgreSQL URL, HTTPS email base URL, and STARTTLS SMTP. Configure GOOGLE_CLIENT_ID
if using POST `/auth/google`. Run migration and seed as deliberate deployment
steps before starting a single Uvicorn worker. Arbitrary development rewards and
global season mutation are unavailable outside dev/test.

Do not use the baseline to reset staging or production data. The uploaded
instructions authorized disposable development data only.
