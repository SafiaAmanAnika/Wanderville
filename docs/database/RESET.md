# Disposable local database reset

The uploaded database addendum (sections 57-97) explicitly replaces the previous
seven-revision history with `0001_initial_schema`. No old data is migrated.
The original schema/revision audit is in [LEGACY_AUDIT.md](LEGACY_AUDIT.md).

No existing user database was connected to, dropped, or reset during this work.
The application never drops a database. Follow these commands only for a local,
disposable WanderVille development database.

1. Stop FastAPI and other connections.
2. Check `.env`: WANDERVILLE_ENV must be dev and DATABASE_URL must point to your
   intended local development database. Do not proceed for production, valuable
   staging data, or an uncertain target.
3. Optionally back up the old local database, replacing `OLD_LOCAL_DB` explicitly:

```powershell
pg_dump -h 127.0.0.1 -U postgres -Fc -f wanderville_old_backup.dump OLD_LOCAL_DB
```

4. Prefer creating a fresh database without dropping the old one:

```powershell
createdb -h 127.0.0.1 -U postgres -O wanderville_app wanderville_dev_clean
```

5. Point `.env` to `wanderville_dev_clean`, then from `code/server` run:

```powershell
python -m alembic upgrade head
python -m app.db.seed
python -m alembic check
python -m alembic current
python -m pytest -q
python -m uvicorn main:app --reload --no-access-log
```

6. If you explicitly choose to reuse the disposable `wanderville_dev` name,
   instead of step 4, run the following against localhost only. `--interactive`
   asks you to confirm the exact database name being removed:

```powershell
dropdb -h 127.0.0.1 -U postgres --interactive --if-exists wanderville_dev
createdb -h 127.0.0.1 -U postgres -O wanderville_app wanderville_dev
```

Do not run `alembic stamp head` over an old schema, and do not copy an old
`alembic_version` row. The new database must be built by the baseline migration.
`alembic downgrade base` deliberately removes all application tables; it is only
for disposable validation and is not a data-preserving undo.

Future schema changes should add forward migrations to this new baseline.
