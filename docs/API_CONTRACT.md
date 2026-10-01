> Historical baseline documentation. For the current extension, see `BACKEND_UPDATE_GUIDE.md`, `SRS_BACKEND_AUDIT.md`, `NEW_API_REFERENCE.md`, and `database/REMAINING_FEATURES.md`. Existing legacy routes remain supported.

# Stable Godot API contract

All normal JSON successes have `success: true`, `data`, and `message`. Controlled
errors have `success: false`, `error`, and `message`. Validation failures use this
same error envelope with HTTP 422 and never echo raw inputs. Protected routes
require `Authorization: Bearer <access_token>`.

## Authentication

| Method/path | Request | Success data |
| --- | --- | --- |
| POST `/auth/signup` | username, email, password, optional display_name | Public player |
| POST `/auth/login` | username, password | access_token, refresh_token, token_type, player |
| POST `/auth/google` | id_token | Same token/player shape as login |
| POST `/auth/refresh` | refresh_token | Replacement access_token, refresh_token, token_type |
| POST `/auth/logout` | refresh_token | null |
| GET `/auth/verify-email` | token query parameter | Public player |
| POST `/auth/resend-verification` | email | null, generic confirmation |
| POST `/auth/forgot-password` | email | null, generic confirmation |
| POST `/auth/reset-password` | token, new_password | null |
| PUT `/auth/change-password` | current_password, new_password; bearer token | null |
| GET `/auth/me` | bearer token | Public player |

Public player fields remain id, username, display_name, email, email_verified,
avatar_url, oauth_provider, created_at, is_active, position_x, position_y. Position
fields are response-only zero placeholders because no current position-writing
API is integrated. Password hashes and internal security fields are never exposed.

Password rules remain the implemented eight-character minimum, uppercase,
lowercase, digit, special character, maximum 128; this is stricter than the older
six-character SRS story. Usernames remain 3-32 letters, digits, `_` or `-`.

The login UI checks `ACCOUNT_LOCKED` and `EMAIL_NOT_VERIFIED`; those codes are
preserved/fixed at the boundary. Verification and reset screens check
`TOKEN_EXPIRED`, `ALREADY_VERIFIED` and `INVALID_TOKEN`, so those exact codes are
returned: a spent verification link for an already-verified account answers
`ALREADY_VERIFIED`, a spent reset link answers `INVALID_TOKEN`, and an unused
expired link of either kind answers `TOKEN_EXPIRED`. Google browser redirect/deep-link
completion is an existing integration gap; POST `/auth/google` verifies an ID
token correctly but does not create a browser authorization flow.

## Inventory, economy and worlds

| Method/path | Request | Success data / policy |
| --- | --- | --- |
| GET `/inventory/` | bearer | items, total_items, total_quantity |
| GET `/inventory/catalog` | bearer | List of item definitions |
| GET `/inventory/catalog/{season}` | bearer | Matching/all-season definitions |
| POST `/inventory/add` | item_code, quantity=1, location=inventory | Stack; dev/test only |
| POST `/inventory/remove` | item_code, quantity=1 | Remaining stack or null |
| POST `/inventory/use` | item_code, quantity=1 | Requires catalog usable flag |
| POST `/inventory/transfer` | to_player_username, item_code, quantity | transferred, item_code, quantity, to |
| GET `/economy/` | bearer | player_id, aura_balance, taka_balance, coin_balance=0, total_earned, total_spent |
| POST `/economy/earn` | amount, currency_type=taka, description | Balance; dev/test only |
| POST `/economy/spend` | amount, currency_type=taka, description | Balance; spends own Aura without claiming an item reward |
| GET `/economy/xp` | bearer | player_id, current_xp, total_xp, level, xp_to_next_level, title=null |
| POST `/economy/xp/gain` | xp_amount, source | XP; dev/test only |
| GET `/economy/transactions` | optional limit=20, max=100 | Own recent signed ledger entries |
| GET `/world/me` | bearer | id, owner_id, name, created_at, updated_at, tiles={} |
| GET `/world/state` | bearer | current_season, season_start_time, season_duration_minutes, day_night_cycle_minutes, current_time_of_day, is_raining, weather |
| POST `/world/advance-season` | bearer | Disabled unless local dev switch is explicitly enabled and no crops are active |
| PUT `/world/tile`, `/world/tiles` | bearer | HTTP 410; unused arbitrary JSON mutation retired |

`item_code` is always returned. Deprecated `item_type` input/output aliases remain
at the API boundary only. Conflicting aliases are rejected. Only `inventory`
location is implemented. Amounts/quantities/XP are strict positive integers up to
1,000,000. Stack additions also enforce catalog max_stack (99 for seeded items).

Aura is the sole database currency. `taka_balance` maps to Aura; `coin_balance` is
a constant zero compatibility field. `currency_type` accepts `taka` or `aura`,
not a fictional second currency. XP thresholds start at 100 and multiply by 1.5
with integer truncation per level, preserving the prior progression formula.

## Farming

| Method/path | Request | Success data |
| --- | --- | --- |
| GET `/farm/plots` | bearer | plots, player_id |
| POST `/farm/till` | x, y | Tile DTO; additive endpoint |
| POST `/farm/plant` | x, y, item_code | plot, water_remaining=null |
| POST `/farm/water` | plot_id | Tile DTO |
| POST `/farm/harvest` | plot_id | plot, item_code, crop_type, quantity |

The exact Godot planting request `{ "x": 3, "y": 4, "item_code": "wheat" }`
works. `crop_type` remains an optional legacy input/output alias. Coordinates are
strict integers in 0..32767; this is an input safety range, not proof that a tile
belongs to a valid Godot farm region. Static map geometry is not duplicated.

Tile DTO fields: id, x, y, item_code, crop_type, is_tilled,
growth_progress_seconds, growth_stage, is_watered, planted_at, ready,
is_harvested. `is_harvested` is an API compatibility projection of an empty tile;
it is not persisted. A tile remains after harvest and can be planted again.

Planting validates the catalog/season, consumes one matching item by default,
and grants catalog xp_reward. It may till an empty coordinate implicitly because
the frozen client has no till call. Harvest grants one matching catalog item and
xp_reward atomically. The existing catalog identifies seeds/produce by the same
code; distinct seed/produce partitions need a separate future catalog/integration
decision. New accounts start with empty inventories and zero Aura by default.

Growth has four stages (0..3). Watering advances at most one stage; growth pauses
at its next stage until another watering. No crop dies while dry. Base duration
comes only from ItemDefinition. Seasonal rate defaults are summer 1.25, spring
1.0, autumn 0.9, winter 0.75; these numerical balancing choices are configurable
because the SRS specifies ordering but not numbers. Growth integrates across
season boundaries. GET computes a read-only projection; mutations save progress.

Repeated harvest returns FARM_EMPTY without awarding anything. Not-ready harvest,
occupied coordinates, out-of-season planting, insufficient seeds and overfull
stacks leave all participating state unchanged. Water bucket quantity remains
client-owned: the API neither invents a balance nor rejects watering for a bucket
it cannot observe.

## Health

GET `/health` returns `{ "success": true, "data": { "status": "ok" }, "message": "OK" }`
without querying, seeding, or modifying the database. `/docs` and `/openapi.json`
remain available.
