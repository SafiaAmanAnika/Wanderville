# Database design for the remaining features

## Relationship and transaction decisions

| Concern | Design |
| --- | --- |
| Account-owned state | Profile, house and pet use `player_id` as their primary key; deletion cascades from players. Pets are adopted only after character selection. |
| Catalog versus inventory | `item_definitions` is shared reference data. `item_rules` supplies partition/level/seed-to-produce/food/equipment semantics. Inventory keeps its original unique player/item/location identity. |
| Achievements and daily tasks | Definitions are shared; player progress has a composite player/goal/period key. Lifetime goals use period -1; daily goals use the global game-day number. Rewards are recorded in the existing Aura ledger in the same transaction. |
| Friendships and blocks | A canonical low/high pair prevents duplicate opposite-direction requests. The requester is a participant and status is constrained. Blocks are directed and checked in both directions. |
| Gifts | Sending removes items from the sender into a gift row. Claiming adds to the recipient and marks claimed atomically; capacity errors preserve escrow. |
| Trades | Proposals do not reserve items; the SRS says availability must be rechecked on acceptance. Acceptance locks both players in ascending ID order, removes both offers, then adds both receipts, then closes the trade. Any failure rolls back all changes. |
| Replay | Purchase and gift/trade creation keys are scoped to the sender. Reusing a key with different payload is a conflict. Claims/catches/upgrades have resolved flags, tokens or expected-tier guards. |
| Online state | Persisted presence is indexed by room/time; TTL determines whether a player is visible. Movement sequences reject stale updates. Proximity chat materializes recipients at send time. |
| Scheduled work | The world clock derives season/day/weather; a separately run bounded worker advances/waters crops and emits deduplicated alerts/events. No API-startup migration or duplicated in-process scheduler. |
| Notifications | Owner-scoped inbox index, descending ID cursor, read/dismiss flags and unique event keys for worker deduplication. |
| Save/load | Server mutations are committed as normalized state, not an opaque client save blob. Client-only visuals are excluded. |

## Integrity and access

All mutations derive the acting player from the existing access token. Route input never supplies an authoritative acting-player ID, Aura award, catch result or XP award. Existing development-only award endpoints remain disabled outside dev/test. Multi-player inventory operations acquire player locks in stable order. SQLite is a development/test adapter; PostgreSQL is required by the existing non-development configuration policy.

Catalog foreign keys normally restrict deletion because reference items must not disappear while in use. Owned progress cascades on account deletion. Gifts/trades/messages involving a deleted account are also removed; an already claimed inventory item belongs to its recipient and is not reversed. This retention policy is documented for review.

## New table definitions

Types below come from the delivered ORM metadata. `PK` means primary key; `required` means NOT NULL. Indexes and constraints are reflected in the additive Alembic revisions. The full fresh PostgreSQL DDL is in `POSTGRES_SCHEMA.sql`.

### `fishing_spots`

| Column | Type | Integrity / default |
| --- | --- | --- |
| `code` | VARCHAR(32) | PK; required |
| `name` | VARCHAR(64) | required |
| `freezes_in_winter` | BOOLEAN | required; default false |

### `goal_definitions`

| Column | Type | Integrity / default |
| --- | --- | --- |
| `code` | VARCHAR(32) | PK; required |
| `kind` | VARCHAR(16) | required |
| `title` | VARCHAR(128) | required |
| `event` | VARCHAR(32) | required |
| `target` | INTEGER | required |
| `aura_reward` | INTEGER | required |

Checks: `target > 0 AND aura_reward >= 0`; `kind IN ('achievement','daily')`.

Indexes: `ix_goal_definitions_event` (event).

### `house_tiers`

| Column | Type | Integrity / default |
| --- | --- | --- |
| `tier` | INTEGER | PK; required |
| `name` | VARCHAR(64) | required |
| `cost` | INTEGER | required |
| `required_level` | INTEGER | required; default 1 |

Checks: `tier >= 1 AND cost >= 0 AND required_level >= 1`.

### `collection_entries`

| Column | Type | Integrity / default |
| --- | --- | --- |
| `player_id` | INTEGER | PK; required; FK players.id; delete CASCADE |
| `item_code` | VARCHAR(32) | PK; required; FK item_definitions.item_code; delete restrict |
| `first_obtained_at` | DATETIME | required; default now() |

### `decorations`

| Column | Type | Integrity / default |
| --- | --- | --- |
| `id` | INTEGER | PK; required |
| `player_id` | INTEGER | required; FK players.id; delete CASCADE |
| `item_code` | VARCHAR(32) | required; FK item_definitions.item_code; delete restrict |
| `x` | INTEGER | required |
| `y` | INTEGER | required |

Checks: `UNIQUE (player_id, x, y)`; `x BETWEEN 0 AND 32767 AND y BETWEEN 0 AND 32767`.

Indexes: `ix_decorations_player_id` (player_id).

### `direct_messages`

| Column | Type | Integrity / default |
| --- | --- | --- |
| `id` | INTEGER | PK; required |
| `sender_id` | INTEGER | required; FK players.id; delete CASCADE |
| `receiver_id` | INTEGER | required; FK players.id; delete CASCADE |
| `body` | VARCHAR(500) | required |
| `created_at` | DATETIME | required; default now() |

Checks: `sender_id <> receiver_id`.

Indexes: `ix_direct_messages_sender_id` (sender_id); `ix_dm_inbox` (receiver_id, id).

### `encounter_hints`

| Column | Type | Integrity / default |
| --- | --- | --- |
| `player_id` | INTEGER | PK; required; FK players.id; delete CASCADE |
| `feature` | VARCHAR(32) | PK; required |

### `feedback`

| Column | Type | Integrity / default |
| --- | --- | --- |
| `id` | INTEGER | PK; required |
| `player_id` | INTEGER | required; FK players.id; delete CASCADE |
| `message` | VARCHAR(2000) | required |
| `created_at` | DATETIME | required; default now() |

Indexes: `ix_feedback_player_id` (player_id).

### `fishing_sessions`

| Column | Type | Integrity / default |
| --- | --- | --- |
| `player_id` | INTEGER | PK; required; FK players.id; delete CASCADE |
| `cast_id` | VARCHAR(64) | required |
| `spot_code` | VARCHAR(32) | required; FK fishing_spots.code; delete restrict |
| `rod_code` | VARCHAR(32) | required; FK item_definitions.item_code; delete restrict |
| `item_code` | VARCHAR(32) | required; FK item_definitions.item_code; delete restrict |
| `bite_at` | DATETIME | required |
| `expires_at` | DATETIME | required |
| `resolved` | BOOLEAN | required; default false |

Checks: `expires_at > bite_at`; `UNIQUE (cast_id)`.

### `friendships`

| Column | Type | Integrity / default |
| --- | --- | --- |
| `low_id` | INTEGER | PK; required; FK players.id; delete CASCADE |
| `high_id` | INTEGER | PK; required; FK players.id; delete CASCADE |
| `requested_by` | INTEGER | required; FK players.id; delete CASCADE |
| `status` | VARCHAR(16) | required; default pending |

Checks: `requested_by = low_id OR requested_by = high_id`; `low_id < high_id`; `status IN ('pending','accepted')`.

Indexes: `ix_friend_high_status` (high_id, status).

### `gifts`

| Column | Type | Integrity / default |
| --- | --- | --- |
| `id` | INTEGER | PK; required |
| `sender_id` | INTEGER | required; FK players.id; delete CASCADE |
| `receiver_id` | INTEGER | required; FK players.id; delete CASCADE |
| `request_id` | VARCHAR(64) | required |
| `item_code` | VARCHAR(32) | required; FK item_definitions.item_code; delete restrict |
| `quantity` | INTEGER | required |
| `claimed` | BOOLEAN | required; default false |
| `created_at` | DATETIME | required; default now() |

Checks: `UNIQUE (sender_id, request_id)`; `sender_id <> receiver_id AND quantity > 0`.

Indexes: `ix_gift_mailbox` (receiver_id, claimed, id).

### `goal_progress`

| Column | Type | Integrity / default |
| --- | --- | --- |
| `player_id` | INTEGER | PK; required; FK players.id; delete CASCADE |
| `goal_code` | VARCHAR(32) | PK; required; FK goal_definitions.code; delete restrict |
| `period` | INTEGER | PK; required |
| `progress` | INTEGER | required; default 0 |
| `rewarded` | BOOLEAN | required; default false |

Checks: `progress >= 0`.

### `ground_drops`

| Column | Type | Integrity / default |
| --- | --- | --- |
| `id` | INTEGER | PK; required |
| `player_id` | INTEGER | required; FK players.id; delete CASCADE |
| `item_code` | VARCHAR(32) | required; FK item_definitions.item_code; delete restrict |
| `spot_code` | VARCHAR(32) | required; FK fishing_spots.code; delete restrict |
| `expires_at` | DATETIME | required |
| `claimed` | BOOLEAN | required; default false |

Indexes: `ix_ground_owner_expiry` (player_id, expires_at).

### `item_rules`

| Column | Type | Integrity / default |
| --- | --- | --- |
| `item_code` | VARCHAR(32) | PK; required; FK item_definitions.item_code; delete CASCADE |
| `partition` | VARCHAR(32) | required |
| `required_level` | INTEGER | required; default 1 |
| `harvest_code` | VARCHAR(32) | FK item_definitions.item_code; delete restrict |
| `pet_food` | BOOLEAN | required; default false |
| `pet_accessory` | BOOLEAN | required; default false |
| `fishing_rod` | BOOLEAN | required; default false |

Checks: `partition IN ('seeds','crops','fish','rare_materials','tools','houses')`; `required_level >= 1`.

### `login_streaks`

| Column | Type | Integrity / default |
| --- | --- | --- |
| `player_id` | INTEGER | PK; required; FK players.id; delete CASCADE |
| `last_date` | DATE |  |
| `streak` | INTEGER | required; default 0 |

Checks: `streak >= 0`.

### `nearby_messages`

| Column | Type | Integrity / default |
| --- | --- | --- |
| `id` | INTEGER | PK; required |
| `sender_id` | INTEGER | required; FK players.id; delete CASCADE |
| `body` | VARCHAR(500) | required |
| `expires_at` | DATETIME | required |

Indexes: `ix_nearby_expiry` (expires_at).

### `notifications`

| Column | Type | Integrity / default |
| --- | --- | --- |
| `id` | INTEGER | PK; required |
| `player_id` | INTEGER | required; FK players.id; delete CASCADE |
| `kind` | VARCHAR(32) | required |
| `message` | VARCHAR(512) | required |
| `target` | VARCHAR(128) |  |
| `event_key` | VARCHAR(128) |  |
| `is_read` | BOOLEAN | required; default false |
| `dismissed` | BOOLEAN | required; default false |
| `created_at` | DATETIME | required; default now() |

Checks: `UNIQUE (player_id, event_key)`.

Indexes: `ix_notification_inbox` (player_id, dismissed, id).

### `player_blocks`

| Column | Type | Integrity / default |
| --- | --- | --- |
| `player_id` | INTEGER | PK; required; FK players.id; delete CASCADE |
| `blocked_id` | INTEGER | PK; required; FK players.id; delete CASCADE |

Checks: `player_id <> blocked_id`.

Indexes: `ix_block_reverse` (blocked_id, player_id).

### `player_houses`

| Column | Type | Integrity / default |
| --- | --- | --- |
| `player_id` | INTEGER | PK; required; FK players.id; delete CASCADE |
| `tier` | INTEGER | required; default 1; FK house_tiers.tier; delete restrict |

### `player_pets`

| Column | Type | Integrity / default |
| --- | --- | --- |
| `player_id` | INTEGER | PK; required; FK players.id; delete CASCADE |
| `species` | VARCHAR(32) | required; default cat |
| `name` | VARCHAR(32) | required; default Mochi |
| `affection` | INTEGER | required; default 0 |
| `accessory_code` | VARCHAR(32) | FK item_definitions.item_code; delete restrict |
| `last_interaction_at` | DATETIME |  |
| `fetch_started_at` | DATETIME |  |

Checks: `affection BETWEEN 0 AND 100`.

### `player_presence`

| Column | Type | Integrity / default |
| --- | --- | --- |
| `player_id` | INTEGER | PK; required; FK players.id; delete CASCADE |
| `room` | VARCHAR(64) | required |
| `x` | FLOAT | required |
| `y` | FLOAT | required |
| `sequence` | INTEGER | required; default 0 |
| `updated_at` | DATETIME | required |
| `emote` | VARCHAR(16) |  |
| `emote_until` | DATETIME |  |

Checks: `sequence >= 0`.

Indexes: `ix_presence_room_time` (room, updated_at).

### `player_profiles`

| Column | Type | Integrity / default |
| --- | --- | --- |
| `player_id` | INTEGER | PK; required; FK players.id; delete CASCADE |
| `character_code` | VARCHAR(32) |  |
| `map_code` | VARCHAR(32) | required; default campus |
| `status_message` | VARCHAR(140) | required; default '' |
| `water_charges` | INTEGER | required; default 20 |
| `music_volume` | INTEGER | required; default 100 |
| `effects_volume` | INTEGER | required; default 100 |
| `fullscreen` | BOOLEAN | required; default false |
| `tutorial_step` | INTEGER | required; default 0 |
| `last_seen_at` | DATETIME |  |
| `last_saved_at` | DATETIME |  |

Checks: `tutorial_step BETWEEN 0 AND 3`; `music_volume BETWEEN 0 AND 100 AND effects_volume BETWEEN 0 AND 100`; `water_charges BETWEEN 0 AND 20`.

Indexes: `ix_player_profiles_last_seen_at` (last_seen_at).

### `player_reports`

| Column | Type | Integrity / default |
| --- | --- | --- |
| `id` | INTEGER | PK; required |
| `reporter_id` | INTEGER | required; FK players.id; delete CASCADE |
| `reported_id` | INTEGER | required; FK players.id; delete CASCADE |
| `reason` | VARCHAR(32) | required |
| `details` | VARCHAR(1000) | required |
| `created_at` | DATETIME | required; default now() |

Checks: `reporter_id <> reported_id`.

Indexes: `ix_player_reports_reported_id` (reported_id); `ix_player_reports_reporter_id` (reporter_id).

### `player_statistics`

| Column | Type | Integrity / default |
| --- | --- | --- |
| `player_id` | INTEGER | PK; required; FK players.id; delete CASCADE |
| `event` | VARCHAR(32) | PK; required |
| `value` | INTEGER | required; default 0 |

Checks: `value >= 0`.

### `shop_purchases`

| Column | Type | Integrity / default |
| --- | --- | --- |
| `player_id` | INTEGER | PK; required; FK players.id; delete CASCADE |
| `request_id` | VARCHAR(64) | PK; required |
| `item_code` | VARCHAR(32) | required; FK item_definitions.item_code; delete restrict |
| `quantity` | INTEGER | required |
| `unit_price` | INTEGER | required |
| `game_day` | INTEGER | required |

Checks: `quantity > 0 AND unit_price >= 0`.

Indexes: `ix_purchase_player_day` (player_id, game_day).

### `trades`

| Column | Type | Integrity / default |
| --- | --- | --- |
| `id` | INTEGER | PK; required |
| `sender_id` | INTEGER | required; FK players.id; delete CASCADE |
| `receiver_id` | INTEGER | required; FK players.id; delete CASCADE |
| `request_id` | VARCHAR(64) | required |
| `offered_code` | VARCHAR(32) | required; FK item_definitions.item_code; delete restrict |
| `offered_quantity` | INTEGER | required |
| `wanted_code` | VARCHAR(32) | required; FK item_definitions.item_code; delete restrict |
| `wanted_quantity` | INTEGER | required |
| `status` | VARCHAR(16) | required; default pending |

Checks: `status IN ('pending','accepted','declined','cancelled')`; `UNIQUE (sender_id, request_id)`; `sender_id <> receiver_id AND offered_quantity > 0 AND wanted_quantity > 0`.

Indexes: `ix_trade_receiver_status` (receiver_id, status, id); `ix_trades_sender_id` (sender_id).

### `world_events`

| Column | Type | Integrity / default |
| --- | --- | --- |
| `code` | VARCHAR(64) | PK; required |
| `title` | VARCHAR(128) | required |
| `starts_at` | DATETIME | required |
| `ends_at` | DATETIME | required |
| `item_code` | VARCHAR(32) | required; FK item_definitions.item_code; delete restrict |
| `quantity` | INTEGER | required; default 1 |

Checks: `ends_at > starts_at AND quantity > 0`.

Indexes: `ix_event_window` (starts_at, ends_at).

### `event_claims`

| Column | Type | Integrity / default |
| --- | --- | --- |
| `player_id` | INTEGER | PK; required; FK players.id; delete CASCADE |
| `event_code` | VARCHAR(64) | PK; required; FK world_events.code; delete CASCADE |

### `nearby_message_recipients`

| Column | Type | Integrity / default |
| --- | --- | --- |
| `message_id` | INTEGER | PK; required; FK nearby_messages.id; delete CASCADE |
| `player_id` | INTEGER | PK; required; FK players.id; delete CASCADE |

Indexes: `ix_nearby_message_recipients_player_id` (player_id).

### `social_invites`

| Column | Type | Integrity / default |
| --- | --- | --- |
| `id` | INTEGER | PK; required |
| `sender_id` | INTEGER | required; FK players.id; delete CASCADE |
| `receiver_id` | INTEGER | required; FK players.id; delete CASCADE |
| `world_id` | INTEGER | required; FK player_worlds.id; delete CASCADE |
| `expires_at` | DATETIME | required |
| `accepted` | BOOLEAN | required; default false |

Checks: `sender_id <> receiver_id`.

Indexes: `ix_invite_receiver_expiry` (receiver_id, expires_at); `ix_social_invites_sender_id` (sender_id).

## Performance scope

Indexes target owner-scoped reads, friendship reverse lookups, room/heartbeat discovery, notification/mailbox cursors, message recipients and expiry scans. Nearby presence is capped at 200 candidates; names and block relations are fetched in batches. The worker scans player IDs in batches of 100. Persistent item stacks avoid writing a row per individual item. The shared item catalog is small; seed and definition reads are bounded by its contents.

No production load benchmark, PostgreSQL EXPLAIN ANALYZE or real multi-instance deployment was possible here. Review PostgreSQL plans and latency under realistic concurrency before raising limits. High-frequency presence uses the same database for durability and cross-process visibility; a substantially larger deployment may need a dedicated realtime transport/store while retaining authoritative inventory transactions in PostgreSQL.
