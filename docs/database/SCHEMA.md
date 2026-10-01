# Database schema

Source of truth: the models in `code/server/app/modules/`, registered by
`app/db/model_registry.py`, and the reviewed `0001_initial_schema` migration.

The baseline creates 11 application tables. All timestamps use TIMESTAMPTZ on
PostgreSQL and UTC in Python. Unique constraints create their own PostgreSQL
indexes; redundant indexes on those same keys are intentionally omitted.

## item_definitions

Static master catalog.

| Column | PostgreSQL type | Nullable | Purpose |
| --- | --- | --- | --- |
| `id` | `INTEGER` | no | Surrogate primary key. |
| `item_code` | `VARCHAR(32)` | no | Unique canonical code used by inventory and farming. |
| `name` | `VARCHAR(64)` | no | Human-readable catalog name. |
| `category` | `VARCHAR(32)` | no | Static classification; crop categories or rare_plant are plantable. |
| `max_stack` | `INTEGER` | no | Maximum quantity in one player/item/location stack; service enforced. |
| `sell_value` | `INTEGER` | no | Nonnegative Aura value; no selling endpoint is implemented yet. |
| `buy_value` | `INTEGER` | yes | Optional nonnegative shop price. |
| `growth_time_seconds` | `INTEGER` | yes | Total base growth work for stages 0 to 3; null for non-plants. |
| `season` | `VARCHAR(16)` | no | all or a valid planting season. |
| `xp_reward` | `INTEGER` | no | XP granted for planting and harvesting. |
| `rarity` | `VARCHAR(16)` | no | Static rarity label. |
| `tradable` | `BOOLEAN` | no | Enables inventory transfer. |
| `giftable` | `BOOLEAN` | no | Reference metadata for future gifting. |
| `usable` | `BOOLEAN` | no | Allows the existing use endpoint to consume the item. |
| `placeable` | `BOOLEAN` | no | Reference metadata for future placement. |
| `icon_path` | `VARCHAR(255)` | yes | Optional asset identifier; no assets are stored here. |
| `description` | `VARCHAR(512)` | yes | Optional catalog description. |

Constraints:

- `ck_item_definitions_nonnegative_buy`: `buy_value IS NULL OR buy_value >= 0`.
- `ck_item_definitions_nonnegative_sell`: `sell_value >= 0`.
- `ck_item_definitions_nonnegative_xp`: `xp_reward >= 0`.
- `ck_item_definitions_positive_growth`: `growth_time_seconds IS NULL OR growth_time_seconds > 0`.
- `ck_item_definitions_positive_stack`: `max_stack > 0`.
- `ck_item_definitions_season`: `season IN ('all', 'spring', 'summer', 'autumn', 'winter')`.
- `pk_item_definitions`: `PRIMARY KEY (id)`.
- `uq_item_definitions_item_code`: `UNIQUE (item_code)`.

Additional indexes: `ix_item_definitions_category` (category), `ix_item_definitions_season` (season).

## players

Account/profile identity only.

| Column | PostgreSQL type | Nullable | Purpose |
| --- | --- | --- | --- |
| `id` | `INTEGER` | no | Surrogate primary key. |
| `username` | `VARCHAR(32)` | no | Unique login name (3-32 API characters). |
| `email` | `VARCHAR(255)` | yes | Normalized lowercase unique email; nullable for schema flexibility. |
| `hashed_password` | `VARCHAR(255)` | yes | Argon2 hash; null for Google-only accounts. |
| `display_name` | `VARCHAR(64)` | no | Public display name. |
| `is_active` | `BOOLEAN` | no | Administrative enabled flag; verification never re-enables a disabled account. |
| `email_verified` | `BOOLEAN` | no | Required in addition to is_active for access. |
| `oauth_provider` | `VARCHAR(32)` | yes | External provider; currently google. |
| `oauth_provider_id` | `VARCHAR(255)` | yes | Provider subject; unique with provider. |
| `avatar_url` | `VARCHAR(512)` | yes | Optional profile image URL. |
| `failed_login_attempts` | `INTEGER` | no | Consecutive wrong-password attempts. |
| `locked_until` | `TIMESTAMP WITH TIME ZONE` | yes | UTC end of temporary login lockout. |
| `last_login_at` | `TIMESTAMP WITH TIME ZONE` | yes | Last successful authentication time. |
| `last_login_ip` | `VARCHAR(45)` | yes | Last authentication client address. |
| `token_version` | `INTEGER` | no | Incremented on password changes to invalidate existing access JWTs. |
| `created_at` | `TIMESTAMP WITH TIME ZONE` | no | UTC creation timestamp; database default now(). |
| `updated_at` | `TIMESTAMP WITH TIME ZONE` | no | UTC creation/default timestamp; ORM updates it on mutation. |

Constraints:

- `ck_players_nonnegative_attempts`: `failed_login_attempts >= 0`.
- `ck_players_nonnegative_token_version`: `token_version >= 0`.
- `pk_players`: `PRIMARY KEY (id)`.
- `uq_players_email`: `UNIQUE (email)`.
- `uq_players_oauth_provider`: `UNIQUE (oauth_provider, oauth_provider_id)`.
- `uq_players_username`: `UNIQUE (username)`.

Additional indexes: none; primary/unique keys are indexed..

## world_state

Global season, clock and weather anchors.

| Column | PostgreSQL type | Nullable | Purpose |
| --- | --- | --- | --- |
| `id` | `INTEGER` | no | Singleton key; must equal 1. |
| `current_season` | `VARCHAR(16)` | no | Season at the saved season anchor; current effective season is derived. |
| `season_started_at` | `TIMESTAMP WITH TIME ZONE` | no | UTC cycle anchor. |
| `season_duration_minutes` | `INTEGER` | no | Positive minutes per season. |
| `weather` | `VARCHAR(16)` | no | clear, rain or snow; no weather scheduler is implemented. |
| `day_cycle_anchor_at` | `TIMESTAMP WITH TIME ZONE` | no | UTC day/night cycle anchor. |
| `day_night_cycle_minutes` | `INTEGER` | no | Positive minutes per complete day/night cycle. |
| `updated_at` | `TIMESTAMP WITH TIME ZONE` | no | UTC creation/default timestamp; ORM updates it on mutation. |

Constraints:

- `ck_world_state_positive_day_duration`: `day_night_cycle_minutes > 0`.
- `ck_world_state_positive_season_duration`: `season_duration_minutes > 0`.
- `ck_world_state_season`: `current_season IN ('spring', 'summer', 'autumn', 'winter')`.
- `ck_world_state_singleton`: `id = 1`.
- `ck_world_state_weather`: `weather IN ('clear', 'rain', 'snow')`.
- `pk_world_state`: `PRIMARY KEY (id)`.

Additional indexes: none; primary/unique keys are indexed..

## account_tokens

Single-use verification and reset tokens.

| Column | PostgreSQL type | Nullable | Purpose |
| --- | --- | --- | --- |
| `id` | `INTEGER` | no | Surrogate primary key. |
| `player_id` | `INTEGER` | no | Owning player; deletes cascade from players. |
| `token_hash` | `VARCHAR(64)` | no | Unique SHA-256 digest; raw token is never stored. |
| `token_type` | `VARCHAR(32)` | no | email_verification or password_reset. |
| `expires_at` | `TIMESTAMP WITH TIME ZONE` | no | UTC token expiry. |
| `used_at` | `TIMESTAMP WITH TIME ZONE` | yes | Consumed or invalidated timestamp; null while potentially usable. |
| `created_at` | `TIMESTAMP WITH TIME ZONE` | no | UTC creation timestamp; database default now(). |

Constraints:

- `ck_account_tokens_token_type`: `token_type IN ('email_verification', 'password_reset')`.
- `fk_account_tokens_player_id_players`: `player_id -> players.id; ON DELETE CASCADE`.
- `pk_account_tokens`: `PRIMARY KEY (id)`.
- `uq_account_tokens_token_hash`: `UNIQUE (token_hash)`.

Additional indexes: `ix_account_tokens_player_id` (player_id).

## economy_transactions

Audit ledger for currency changes.

| Column | PostgreSQL type | Nullable | Purpose |
| --- | --- | --- | --- |
| `id` | `INTEGER` | no | Surrogate primary key. |
| `player_id` | `INTEGER` | no | Owning player; deletes cascade from players. |
| `amount` | `BIGINT` | no | Signed nonzero Aura delta. |
| `transaction_type` | `VARCHAR(16)` | no | earn for positive deltas, spend for negative. |
| `reason` | `VARCHAR(255)` | no | Action description, bounded to 255 API characters. |
| `reference_type` | `VARCHAR(32)` | yes | Optional related domain record type. |
| `reference_id` | `VARCHAR(64)` | yes | Optional related record identifier. |
| `created_at` | `TIMESTAMP WITH TIME ZONE` | no | UTC creation timestamp; database default now(). |

Constraints:

- `ck_economy_transactions_signed_amount`: `(transaction_type = 'earn' AND amount > 0) OR (transaction_type = 'spend' AND amount < 0)`.
- `fk_economy_transactions_player_id_players`: `player_id -> players.id; ON DELETE CASCADE`.
- `pk_economy_transactions`: `PRIMARY KEY (id)`.

Additional indexes: `ix_economy_transactions_created_at` (created_at), `ix_economy_transactions_player_id` (player_id).

## inventory_items

Player catalog-item quantities.

| Column | PostgreSQL type | Nullable | Purpose |
| --- | --- | --- | --- |
| `id` | `INTEGER` | no | Surrogate primary key. |
| `player_id` | `INTEGER` | no | Owning player; deletes cascade from players. |
| `item_code` | `VARCHAR(32)` | no | Canonical catalog identifier. |
| `quantity` | `INTEGER` | no | Strictly positive quantity; zero stacks are deleted. |
| `slot_index` | `INTEGER` | yes | Optional nonnegative slot; not assigned by current gameplay. |
| `location` | `VARCHAR(16)` | no | Only inventory is currently implemented. |
| `created_at` | `TIMESTAMP WITH TIME ZONE` | no | UTC creation timestamp; database default now(). |
| `updated_at` | `TIMESTAMP WITH TIME ZONE` | no | UTC creation/default timestamp; ORM updates it on mutation. |

Constraints:

- `ck_inventory_items_nonnegative_slot`: `slot_index IS NULL OR slot_index >= 0`.
- `ck_inventory_items_positive_quantity`: `quantity > 0`.
- `ck_inventory_items_supported_location`: `location = 'inventory'`.
- `fk_inventory_items_item_code_item_definitions`: `item_code -> item_definitions.item_code; ON DELETE NO ACTION`.
- `fk_inventory_items_player_id_players`: `player_id -> players.id; ON DELETE CASCADE`.
- `pk_inventory_items`: `PRIMARY KEY (id)`.
- `uq_inventory_items_player_id`: `UNIQUE (player_id, item_code, location)`.

Additional indexes: `ix_inventory_items_item_code` (item_code), `ix_inventory_items_player_id` (player_id), `ix_inventory_player_location` (player_id, location).

## player_economy

One canonical Aura balance per player.

| Column | PostgreSQL type | Nullable | Purpose |
| --- | --- | --- | --- |
| `player_id` | `INTEGER` | no | Owning player; deletes cascade from players. |
| `aura_balance` | `BIGINT` | no | Nonnegative current Aura; API also exposes this as taka_balance. |
| `total_earned` | `BIGINT` | no | Nonnegative lifetime credited amount. |
| `total_spent` | `BIGINT` | no | Nonnegative lifetime debited amount. |
| `updated_at` | `TIMESTAMP WITH TIME ZONE` | no | UTC creation/default timestamp; ORM updates it on mutation. |

Constraints:

- `ck_player_economy_nonnegative_aura_balance`: `aura_balance >= 0`.
- `ck_player_economy_nonnegative_total_earned`: `total_earned >= 0`.
- `ck_player_economy_nonnegative_total_spent`: `total_spent >= 0`.
- `fk_player_economy_player_id_players`: `player_id -> players.id; ON DELETE CASCADE`.
- `pk_player_economy`: `PRIMARY KEY (player_id)`.

Additional indexes: none; primary/unique keys are indexed..

## player_experience

Lifetime XP and level, with API-only current progress.

| Column | PostgreSQL type | Nullable | Purpose |
| --- | --- | --- | --- |
| `player_id` | `INTEGER` | no | Owning player; deletes cascade from players. |
| `total_xp` | `BIGINT` | no | Authoritative nonnegative lifetime XP. |
| `level` | `INTEGER` | no | Stored progression level, recomputed from total_xp on each grant. |
| `updated_at` | `TIMESTAMP WITH TIME ZONE` | no | UTC creation/default timestamp; ORM updates it on mutation. |

Constraints:

- `ck_player_experience_nonnegative_xp`: `total_xp >= 0`.
- `ck_player_experience_positive_level`: `level >= 1`.
- `fk_player_experience_player_id_players`: `player_id -> players.id; ON DELETE CASCADE`.
- `pk_player_experience`: `PRIMARY KEY (player_id)`.

Additional indexes: none; primary/unique keys are indexed..

## player_worlds

One personal world per player.

| Column | PostgreSQL type | Nullable | Purpose |
| --- | --- | --- | --- |
| `id` | `INTEGER` | no | Surrogate primary key. |
| `owner_id` | `INTEGER` | no | Unique owning player; at most one world per player, cascading deletion. |
| `name` | `VARCHAR(64)` | no | Personal world name. No unexplained tiles JSON is persisted. |
| `created_at` | `TIMESTAMP WITH TIME ZONE` | no | UTC creation timestamp; database default now(). |
| `updated_at` | `TIMESTAMP WITH TIME ZONE` | no | UTC creation/default timestamp; ORM updates it on mutation. |

Constraints:

- `fk_player_worlds_owner_id_players`: `owner_id -> players.id; ON DELETE CASCADE`.
- `pk_player_worlds`: `PRIMARY KEY (id)`.
- `uq_player_worlds_owner_id`: `UNIQUE (owner_id)`.

Additional indexes: none; primary/unique keys are indexed..

## refresh_tokens

Hashed rotating sessions.

| Column | PostgreSQL type | Nullable | Purpose |
| --- | --- | --- | --- |
| `id` | `INTEGER` | no | Surrogate primary key. |
| `player_id` | `INTEGER` | no | Owning player; deletes cascade from players. |
| `token_hash` | `VARCHAR(64)` | no | Unique SHA-256 digest; raw token is never stored. |
| `device_info` | `VARCHAR(255)` | yes | Optional device/session label. |
| `expires_at` | `TIMESTAMP WITH TIME ZONE` | no | UTC token expiry. |
| `revoked_at` | `TIMESTAMP WITH TIME ZONE` | yes | Null while usable; timestamp after rotation/logout/reset. |
| `created_at` | `TIMESTAMP WITH TIME ZONE` | no | UTC creation timestamp; database default now(). |

Constraints:

- `fk_refresh_tokens_player_id_players`: `player_id -> players.id; ON DELETE CASCADE`.
- `pk_refresh_tokens`: `PRIMARY KEY (id)`.
- `uq_refresh_tokens_token_hash`: `UNIQUE (token_hash)`.

Additional indexes: `ix_refresh_tokens_player_id` (player_id).

## farm_tiles

Reusable persisted soil and crop state.

| Column | PostgreSQL type | Nullable | Purpose |
| --- | --- | --- | --- |
| `id` | `INTEGER` | no | Surrogate primary key. |
| `world_id` | `INTEGER` | no | Owning private world; deletion cascades. |
| `x` | `INTEGER` | no | Grid X coordinate. |
| `y` | `INTEGER` | no | Grid Y coordinate. |
| `is_tilled` | `BOOLEAN` | no | Tile is prepared for planting; remains true after harvest. |
| `crop_item_code` | `VARCHAR(32)` | yes | Nullable catalog FK; null means no crop. |
| `planted_at` | `TIMESTAMP WITH TIME ZONE` | yes | UTC planting time; cleared on harvest. |
| `growth_progress_seconds` | `FLOAT` | no | Accumulated growth work; dry time never advances it. |
| `growth_stage` | `INTEGER` | no | Last persisted stage, 0 to 3. API computes a current projection. |
| `last_growth_update_at` | `TIMESTAMP WITH TIME ZONE` | yes | UTC progress checkpoint; null on an empty tile. |
| `is_watered` | `BOOLEAN` | no | Current stage has been watered. Cleared at the next stage or harvest. |
| `watered_at` | `TIMESTAMP WITH TIME ZONE` | yes | UTC last watering time; cleared on harvest. |
| `created_at` | `TIMESTAMP WITH TIME ZONE` | no | UTC creation timestamp; database default now(). |
| `updated_at` | `TIMESTAMP WITH TIME ZONE` | no | UTC creation/default timestamp; ORM updates it on mutation. |

Constraints:

- `ck_farm_tiles_crop_state`: `(crop_item_code IS NOT NULL AND is_tilled AND planted_at IS NOT NULL AND last_growth_update_at IS NOT NULL) OR (crop_item_code IS NULL AND planted_at IS NULL AND growth_progress_seconds = 0 AND growth_stage = 0 AND NOT is_watered AND watered_at IS NULL AND last_growth_update_at IS NULL)`.
- `ck_farm_tiles_growth_stage`: `growth_stage BETWEEN 0 AND 3`.
- `ck_farm_tiles_nonnegative_coordinates`: `x >= 0 AND y >= 0`.
- `ck_farm_tiles_nonnegative_progress`: `growth_progress_seconds >= 0`.
- `ck_farm_tiles_water_timestamp`: `NOT is_watered OR watered_at IS NOT NULL`.
- `fk_farm_tiles_crop_item_code_item_definitions`: `crop_item_code -> item_definitions.item_code; ON DELETE NO ACTION`.
- `fk_farm_tiles_world_id_player_worlds`: `world_id -> player_worlds.id; ON DELETE CASCADE`.
- `pk_farm_tiles`: `PRIMARY KEY (id)`.
- `uq_farm_tiles_world_id`: `UNIQUE (world_id, x, y)`.

Additional indexes: `ix_farm_tiles_crop_item_code` (crop_item_code), `ix_farm_tiles_world_id` (world_id).

## Removed and mapped concepts

`worlds` is replaced by `player_worlds`; `farm_plots` by `farm_tiles`.
Player position and temporary verification/reset columns are removed.
`taka_balance`/`coin_balance` become canonical `aura_balance`; coin_balance is
only a constant zero response alias. `current_xp`/`xp_to_next_level` are derived,
and the unused XP title is not stored. World tiles JSON, current_time_of_day and
is_raining are not duplicated in persistence; response values are derived or
compatibility placeholders.

The API does not expose database column names as its persistence contract. See
[API_CONTRACT.md](../API_CONTRACT.md) for compatibility fields.
