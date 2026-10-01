# Backend structure

The backend is a modular monolith. Godot uses HTTP/JSON; routers call services;
services enforce game rules and coordinate repositories; repositories query
SQLAlchemy models. Only the server connects to PostgreSQL.

## Responsibilities

| Location | Responsibility |
| --- | --- |
| `code/server/main.py` | Compatibility import for `uvicorn main:app` |
| `app/main.py` | App creation, routers, middleware, central exception handlers, lifespan |
| `app/core/` | Settings, UTC clock, response envelopes, exceptions, logging, rate limiting |
| `app/db/base.py` | Declarative base and constraint naming |
| `app/db/session.py` | Engine/session, request dependency, service transaction boundary |
| `app/db/model_registry.py` | Explicit imports of all 11 schema models |
| `app/db/seed.py`, `catalog.json` | Explicit, idempotent reference data maintenance |
| `app/modules/auth/` | Signup/login, Argon2, JWTs, refresh/account tokens, email, Google verification |
| `app/modules/players/` | Account/profile model, repository, safe public schema |
| `app/modules/world/` | Private worlds and deterministic shared environment projection |
| `app/modules/inventory/` | Authoritative catalog and inventory stacks/transfers |
| `app/modules/economy/` | Aura balance/ledger and XP progression |
| `app/modules/farming/` | Tilling, planting, stage watering, growth, harvest |
| `migrations/` | One reviewed baseline, followed by future forward migrations |
| `tests/` | Contract, auth, inventory, economy, world, farming, database tests |

## Transaction and concurrency rules

A public service action enters `transaction(db)` once. Authentication may already
have started a read transaction; that transaction is included. The boundary commits
once on success and rolls back on every raised failure. Domain helpers ending in
`_internal` flush without committing. Repositories never commit.

Gameplay mutations lock the player's row before reading balances, inventory, or
farm tiles. Transfers lock both players in ascending ID order. This also protects
creation of a previously absent inventory stack or farm tile. PostgreSQL provides
the actual row-lock behavior; SQLite tests do not prove concurrency correctness.
The repository refreshes locked rows to avoid stale ORM identity-map values.

Signup creates Player, PlayerWorld, PlayerEconomy, PlayerExperience, and the
verification token together. Harvest clears the crop, adds inventory, and grants
XP together. Currency and its ledger entry always commit together. Failed login
attempts are committed as their own completed security action before returning
the credential error.

## Add a domain

Create `modules/<feature>/` only when implementing that feature. Add models,
schemas, a repository, service, and router as required. Register models in
`db/model_registry.py`, routers in `app/main.py`, and add a new Alembic revision.
Add contract tests before changing client-facing responses. Keep cross-domain
rewards inside a single caller-owned transaction.

No empty fishing, pets, chat, social, shop, scheduler, or realtime modules are
included. They were not implemented by this refactor.

## Security and operational limits

Arbitrary inventory, Aura and XP award routes only work in `dev`/`test`. Global
season mutation is disabled by default, even in development. Google ID token
verification requires a configured audience. Disabled accounts stay disabled.
Password reset/change revokes all refresh tokens and invalidates access tokens
through `players.token_version`. Logout revokes the supplied refresh token;
its already-issued access token remains valid until expiry (15 minutes by default).

The bounded in-memory rate limiter is local to one process. Use a single worker
for this deployment; shared rate limiting is required before using multiple
workers. Configure reverse proxies to redact token query strings and avoid
logging Authorization headers. Application logs omit query strings, bodies,
passwords, tokens, and database connection strings.

Development mail is saved as private, ignored `.dev-mail/*.eml` files; it is never
printed. Production uses STARTTLS SMTP. Email delivery occurs after the account
transaction. A delivery failure leaves the valid account/token in place so resend
can retry; it logs a generic delivery failure without account or token details.

## Design references

- [SQLAlchemy transaction/session guidance](https://docs.sqlalchemy.org/en/20/orm/session_basics.html)
- [Google backend ID-token verification](https://developers.google.com/identity/sign-in/web/backend-auth)

Current gameplay modules and deployment instructions are documented in `BACKEND_UPDATE_GUIDE.md`; validation evidence is in `VERIFICATION_RESULTS.md`.
