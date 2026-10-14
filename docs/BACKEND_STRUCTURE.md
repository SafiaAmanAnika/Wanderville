# Backend structure

The backend is a modular monolith. Godot uses HTTP/JSON and one WebSocket; routers
call services; services enforce game rules and coordinate repositories;
repositories query SQLAlchemy models. Only the server connects to PostgreSQL.

## Layering rules

Dependencies point downward only:

```
router  ->  service  ->  repository  ->  model
```

* **Routers** bind URLs to a service call and return its result inside the
  response envelope. A router may read the transport (headers, client address,
  frame limits) and nothing else: no game rule, no query, no transaction.
* **Services** hold the rules. They may call another module's *public service*
  to keep cross-domain work inside one transaction. They never import FastAPI.
* **Repositories** read and write rows and never commit. A module with no
  module-specific queries uses `db/repository.Repository` directly instead of
  declaring an empty subclass.
* **Models** are declarative only.

`app/core/` is a leaf: it imports nothing from `app/modules/`. That is why the
shared `Repository` base lives in `app/db/` and the row serializer `public()`
lives in `app/core/responses.py` rather than a grab-bag `core/gameplay.py`.

## Layout

| Location | Responsibility |
| --- | --- |
| `code/server/main.py` | Compatibility import for `uvicorn main:app` |
| `app/main.py` | Composition only: middleware, error registration, routers, lifespan |
| `app/core/config.py` | Every tunable setting, validated at import |
| `app/core/errors.py` | The only place an exception becomes an HTTP status |
| `app/core/exceptions.py` | `AppError` hierarchy raised by services |
| `app/core/responses.py` | Response envelope and `public()` row serializer |
| `app/core/idempotency.py` | `ensure_same_payload` for request-id replay protection |
| `app/core/progression.py` | Level tables, XP awards and unlock rules |
| `app/core/rate_limit.py`, `logging.py`, `clock.py` | In-process limiter, request log, UTC clock |
| `app/db/base.py` | Declarative base and constraint naming |
| `app/db/session.py` | Engine/session, request dependency, `transaction()` boundary |
| `app/db/repository.py` | Shared `Repository` base: `get`, `add`, `list`, `keyset_page` |
| `app/db/model_registry.py` | Explicit imports of all 51 schema models |
| `app/db/seed.py`, `gameplay_seed.py`, `catalog.json` | Idempotent reference data |
| `app/health/router.py` | `/health` and `/ready` probes |
| `app/modules/<feature>/` | One folder per game domain, below |

### Game modules

`auth`, `players`, `world`, `inventory`, `economy`, `farming`, `fishing`,
`housing`, `pets`, `shop`, `progression`, `profile`, `notifications`, `events`,
`social`, `realtime`, `state`.

`players` is deliberately not a full module: it owns the `Player` model,
repository and public schema, and has no service or router of its own.

`state` is a read-only facade that composes six other modules into one response
so the client does not make six sequential calls after each action. It holds no
rules of its own.

### Realtime

`realtime` is the one module with more than the standard five files, because a
socket has genuinely distinct layers. Each file answers one question:

| File | Question |
| --- | --- |
| `router.py` | Which URL maps to which service call? |
| `session.py` | How does one socket live and die? Handshake, framing, idle loop, sequencing, teardown |
| `protocol.py` | What does one inbound message mean? Validation, dispatch, reply shape |
| `connections.py` | Which socket owns a player right now? |
| `service.py` | Presence rules: rooms, movement, snapshots, chat |
| `runtime.py` | Shared voice leases and policy state (process-global, single worker) |
| `voice.py` | The audio mixer and WebRTC negotiation |
| `native_voice.py` | Godot's raw PCM socket |
| `proximity.py` | Who may chat with and hear whom |
| `policy_events.py` | Revoke permissions when a policy row *commits* |

`policy_events.register()` is called explicitly from `app/main.py`. It used to be
attached by importing the module, which meant dropping one import silently
disabled permission revocation.

### Social

An invitation is an *offer*; a visit session is the *occupancy* it produces.
They are separate files because they have different lifetimes and different
failure modes:

| File | Responsibility |
| --- | --- |
| `service.py` | Friendships, blocks, gifts, trades, direct messages, reports |
| `community.py` | Preferences, wishlists, gift reservation, social revisions |
| `farm_invitations.py` | Invitation lifecycle and slot admission |
| `farm_visiting.py` | Visit sessions: visitors list, every exit path, the sweeps |
| `visit_locking.py` | **The one lock order** shared by both of the above |

`FarmVisitService` stays the single public entry point and delegates to
`FarmInvitationService`, so no caller has to know which file owns an action.

## Transactions

A public service action enters `transaction(db)` **once**. Authentication may
already have started a read transaction; that transaction is included. The
boundary commits once on success and rolls back on every raised failure.

`transaction()` **rejects being nested**. An inner exit would commit the outer
caller's half-finished work and make the outer rollback a silent no-op, so this
raises `TransactionBoundaryError` rather than tolerating it. That exception is
deliberately not an `AppError`: it is a programming error and must never be
turned into a client-facing response.

* Public methods own the boundary.
* Helpers suffixed `_internal` flush without committing, for a caller that
  already holds the transaction. This is the *only* such suffix.
* Repositories never commit; they flush so the caller's boundary decides.
* The one deliberate exception is a failed login, which commits as its own
  completed security action before the credential error is raised.
* The realtime socket rolls back at the end of every frame. Its database session
  spans the whole connection, so each frame must end with a clean transaction or
  the next one inherits a half-applied read. Services still own their own writes.

Gameplay mutations lock the player's row before reading balances, inventory or
farm tiles. Transfers lock both players in ascending id order. Farm visiting
locks players ascending and *then* the world row — see `visit_locking.py`. The
repositories refresh locked rows so a value read before taking a lock cannot
leak into the decision made after it. PostgreSQL provides the real row locks;
SQLite tests do not prove concurrency correctness.

## Add a domain

Create `modules/<feature>/` only when implementing that feature. Add models,
schemas, a repository *if the module has its own queries*, a service and a
router. Then:

1. register the models in `db/model_registry.py` (models and `__all__` together);
2. add the router to the `ROUTERS` tuple in `app/main.py`;
3. add a new Alembic revision;
4. add contract tests before changing any client-facing response.

Keep cross-domain rewards inside a single caller-owned transaction. Give every
tunable value a setting in `core/config.py` rather than a literal in a service.

## Deferred imports

A function-local import is a smell, not a style choice. There are seven in the
tree, each a genuine circular-import edge with a comment naming the cycle. If you
add one, do the same — and if you can remove the cycle instead, prefer that.

## Security and operational limits

Arbitrary inventory, Aura and XP award routes only work in `dev`/`test`. Global
season mutation is disabled by default, even in development. Google ID token
verification requires a configured audience. Disabled accounts stay disabled.
Password reset/change revokes all refresh tokens and invalidates access tokens
through `players.token_version`.

The bounded in-memory rate limiter is local to one process. Use a single worker
for this deployment; shared rate limiting is required before using multiple
workers. `runtime` and `voice_hub` are process-global for the same reason.
Configure reverse proxies to redact token query strings and avoid logging
Authorization headers. Application logs omit query strings, bodies, passwords,
tokens and database connection strings.

Development mail is saved as private, ignored `.dev-mail/*.eml` files; it is
never printed. Production uses STARTTLS SMTP. Email delivery occurs after the
account transaction; a delivery failure leaves the valid account in place so
resend can retry.

`/ready` asserts the Alembic revision is at or beyond a numeric floor rather than
matching a revision *name*, so adding a migration does not require editing
application code.

## Design references

- [SQLAlchemy transaction/session guidance](https://docs.sqlalchemy.org/en/20/orm/session_basics.html)
- [Google backend ID-token verification](https://developers.google.com/identity/sign-in/web/backend-auth)

Deployment and startup commands are in `SETUP_AND_HOSTING.md`; validation
evidence is in `VERIFICATION_RESULTS.md`.