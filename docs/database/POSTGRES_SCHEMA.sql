BEGIN;

CREATE TABLE alembic_version (
    version_num VARCHAR(32) NOT NULL,
    CONSTRAINT alembic_version_pkc PRIMARY KEY (version_num)
);

-- Running upgrade  -> 0001_initial_schema

CREATE TABLE item_definitions (
    id SERIAL NOT NULL,
    item_code VARCHAR(32) NOT NULL,
    name VARCHAR(64) NOT NULL,
    category VARCHAR(32) NOT NULL,
    max_stack INTEGER DEFAULT '99' NOT NULL,
    sell_value INTEGER DEFAULT '0' NOT NULL,
    buy_value INTEGER,
    growth_time_seconds INTEGER,
    season VARCHAR(16) DEFAULT 'all' NOT NULL,
    xp_reward INTEGER DEFAULT '0' NOT NULL,
    rarity VARCHAR(16) DEFAULT 'common' NOT NULL,
    tradable BOOLEAN DEFAULT true NOT NULL,
    giftable BOOLEAN DEFAULT true NOT NULL,
    usable BOOLEAN DEFAULT false NOT NULL,
    placeable BOOLEAN DEFAULT false NOT NULL,
    icon_path VARCHAR(255),
    description VARCHAR(512),
    CONSTRAINT pk_item_definitions PRIMARY KEY (id),
    CONSTRAINT ck_item_definitions_season CHECK (season IN ('all', 'spring', 'summer', 'autumn', 'winter')),
    CONSTRAINT ck_item_definitions_nonnegative_buy CHECK (buy_value IS NULL OR buy_value >= 0),
    CONSTRAINT ck_item_definitions_positive_growth CHECK (growth_time_seconds IS NULL OR growth_time_seconds > 0),
    CONSTRAINT ck_item_definitions_positive_stack CHECK (max_stack > 0),
    CONSTRAINT ck_item_definitions_nonnegative_sell CHECK (sell_value >= 0),
    CONSTRAINT ck_item_definitions_nonnegative_xp CHECK (xp_reward >= 0),
    CONSTRAINT uq_item_definitions_item_code UNIQUE (item_code)
);

CREATE INDEX ix_item_definitions_category ON item_definitions (category);

CREATE INDEX ix_item_definitions_season ON item_definitions (season);

CREATE TABLE players (
    id SERIAL NOT NULL,
    username VARCHAR(32) NOT NULL,
    email VARCHAR(255),
    hashed_password VARCHAR(255),
    display_name VARCHAR(64) NOT NULL,
    is_active BOOLEAN DEFAULT true NOT NULL,
    email_verified BOOLEAN DEFAULT false NOT NULL,
    oauth_provider VARCHAR(32),
    oauth_provider_id VARCHAR(255),
    avatar_url VARCHAR(512),
    failed_login_attempts INTEGER DEFAULT '0' NOT NULL,
    locked_until TIMESTAMP WITH TIME ZONE,
    last_login_at TIMESTAMP WITH TIME ZONE,
    last_login_ip VARCHAR(45),
    token_version INTEGER DEFAULT '0' NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    CONSTRAINT pk_players PRIMARY KEY (id),
    CONSTRAINT ck_players_nonnegative_attempts CHECK (failed_login_attempts >= 0),
    CONSTRAINT ck_players_nonnegative_token_version CHECK (token_version >= 0),
    CONSTRAINT uq_players_email UNIQUE (email),
    CONSTRAINT uq_players_oauth_provider UNIQUE (oauth_provider, oauth_provider_id),
    CONSTRAINT uq_players_username UNIQUE (username)
);

CREATE TABLE world_state (
    id SERIAL NOT NULL,
    current_season VARCHAR(16) DEFAULT 'summer' NOT NULL,
    season_started_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    season_duration_minutes INTEGER DEFAULT '10080' NOT NULL,
    weather VARCHAR(16) DEFAULT 'clear' NOT NULL,
    day_cycle_anchor_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    day_night_cycle_minutes INTEGER DEFAULT '40' NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    CONSTRAINT pk_world_state PRIMARY KEY (id),
    CONSTRAINT ck_world_state_season CHECK (current_season IN ('spring', 'summer', 'autumn', 'winter')),
    CONSTRAINT ck_world_state_weather CHECK (weather IN ('clear', 'rain', 'snow')),
    CONSTRAINT ck_world_state_positive_day_duration CHECK (day_night_cycle_minutes > 0),
    CONSTRAINT ck_world_state_singleton CHECK (id = 1),
    CONSTRAINT ck_world_state_positive_season_duration CHECK (season_duration_minutes > 0)
);

CREATE TABLE account_tokens (
    id SERIAL NOT NULL,
    player_id INTEGER NOT NULL,
    token_hash VARCHAR(64) NOT NULL,
    token_type VARCHAR(32) NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    used_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    CONSTRAINT pk_account_tokens PRIMARY KEY (id),
    CONSTRAINT ck_account_tokens_token_type CHECK (token_type IN ('email_verification', 'password_reset')),
    CONSTRAINT fk_account_tokens_player_id_players FOREIGN KEY(player_id) REFERENCES players (id) ON DELETE CASCADE,
    CONSTRAINT uq_account_tokens_token_hash UNIQUE (token_hash)
);

CREATE INDEX ix_account_tokens_player_id ON account_tokens (player_id);

CREATE TABLE economy_transactions (
    id SERIAL NOT NULL,
    player_id INTEGER NOT NULL,
    amount BIGINT NOT NULL,
    transaction_type VARCHAR(16) NOT NULL,
    reason VARCHAR(255) NOT NULL,
    reference_type VARCHAR(32),
    reference_id VARCHAR(64),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    CONSTRAINT pk_economy_transactions PRIMARY KEY (id),
    CONSTRAINT ck_economy_transactions_signed_amount CHECK ((transaction_type = 'earn' AND amount > 0) OR (transaction_type = 'spend' AND amount < 0)),
    CONSTRAINT fk_economy_transactions_player_id_players FOREIGN KEY(player_id) REFERENCES players (id) ON DELETE CASCADE
);

CREATE INDEX ix_economy_transactions_created_at ON economy_transactions (created_at);

CREATE INDEX ix_economy_transactions_player_id ON economy_transactions (player_id);

CREATE TABLE inventory_items (
    id SERIAL NOT NULL,
    player_id INTEGER NOT NULL,
    item_code VARCHAR(32) NOT NULL,
    quantity INTEGER NOT NULL,
    slot_index INTEGER,
    location VARCHAR(16) DEFAULT 'inventory' NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    CONSTRAINT pk_inventory_items PRIMARY KEY (id),
    CONSTRAINT ck_inventory_items_supported_location CHECK (location = 'inventory'),
    CONSTRAINT ck_inventory_items_positive_quantity CHECK (quantity > 0),
    CONSTRAINT ck_inventory_items_nonnegative_slot CHECK (slot_index IS NULL OR slot_index >= 0),
    CONSTRAINT fk_inventory_items_item_code_item_definitions FOREIGN KEY(item_code) REFERENCES item_definitions (item_code),
    CONSTRAINT fk_inventory_items_player_id_players FOREIGN KEY(player_id) REFERENCES players (id) ON DELETE CASCADE,
    CONSTRAINT uq_inventory_items_player_id UNIQUE (player_id, item_code, location)
);

CREATE INDEX ix_inventory_items_item_code ON inventory_items (item_code);

CREATE INDEX ix_inventory_items_player_id ON inventory_items (player_id);

CREATE INDEX ix_inventory_player_location ON inventory_items (player_id, location);

CREATE TABLE player_economy (
    player_id INTEGER NOT NULL,
    aura_balance BIGINT DEFAULT '0' NOT NULL,
    total_earned BIGINT DEFAULT '0' NOT NULL,
    total_spent BIGINT DEFAULT '0' NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    CONSTRAINT pk_player_economy PRIMARY KEY (player_id),
    CONSTRAINT ck_player_economy_nonnegative_aura_balance CHECK (aura_balance >= 0),
    CONSTRAINT ck_player_economy_nonnegative_total_earned CHECK (total_earned >= 0),
    CONSTRAINT ck_player_economy_nonnegative_total_spent CHECK (total_spent >= 0),
    CONSTRAINT fk_player_economy_player_id_players FOREIGN KEY(player_id) REFERENCES players (id) ON DELETE CASCADE
);

CREATE TABLE player_experience (
    player_id INTEGER NOT NULL,
    total_xp BIGINT DEFAULT '0' NOT NULL,
    level INTEGER DEFAULT '1' NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    CONSTRAINT pk_player_experience PRIMARY KEY (player_id),
    CONSTRAINT ck_player_experience_positive_level CHECK (level >= 1),
    CONSTRAINT ck_player_experience_nonnegative_xp CHECK (total_xp >= 0),
    CONSTRAINT fk_player_experience_player_id_players FOREIGN KEY(player_id) REFERENCES players (id) ON DELETE CASCADE
);

CREATE TABLE player_worlds (
    id SERIAL NOT NULL,
    owner_id INTEGER NOT NULL,
    name VARCHAR(64) DEFAULT 'My World' NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    CONSTRAINT pk_player_worlds PRIMARY KEY (id),
    CONSTRAINT fk_player_worlds_owner_id_players FOREIGN KEY(owner_id) REFERENCES players (id) ON DELETE CASCADE,
    CONSTRAINT uq_player_worlds_owner_id UNIQUE (owner_id)
);

CREATE TABLE refresh_tokens (
    id SERIAL NOT NULL,
    player_id INTEGER NOT NULL,
    token_hash VARCHAR(64) NOT NULL,
    device_info VARCHAR(255),
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    revoked_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    CONSTRAINT pk_refresh_tokens PRIMARY KEY (id),
    CONSTRAINT fk_refresh_tokens_player_id_players FOREIGN KEY(player_id) REFERENCES players (id) ON DELETE CASCADE,
    CONSTRAINT uq_refresh_tokens_token_hash UNIQUE (token_hash)
);

CREATE INDEX ix_refresh_tokens_player_id ON refresh_tokens (player_id);

CREATE TABLE farm_tiles (
    id SERIAL NOT NULL,
    world_id INTEGER NOT NULL,
    x INTEGER NOT NULL,
    y INTEGER NOT NULL,
    is_tilled BOOLEAN DEFAULT true NOT NULL,
    crop_item_code VARCHAR(32),
    planted_at TIMESTAMP WITH TIME ZONE,
    growth_progress_seconds FLOAT DEFAULT '0' NOT NULL,
    growth_stage INTEGER DEFAULT '0' NOT NULL,
    last_growth_update_at TIMESTAMP WITH TIME ZONE,
    is_watered BOOLEAN DEFAULT false NOT NULL,
    watered_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    CONSTRAINT pk_farm_tiles PRIMARY KEY (id),
    CONSTRAINT ck_farm_tiles_crop_state CHECK ((crop_item_code IS NOT NULL AND is_tilled AND planted_at IS NOT NULL AND last_growth_update_at IS NOT NULL) OR (crop_item_code IS NULL AND planted_at IS NULL AND growth_progress_seconds = 0 AND growth_stage = 0 AND NOT is_watered AND watered_at IS NULL AND last_growth_update_at IS NULL)),
    CONSTRAINT ck_farm_tiles_water_timestamp CHECK (NOT is_watered OR watered_at IS NOT NULL),
    CONSTRAINT ck_farm_tiles_nonnegative_progress CHECK (growth_progress_seconds >= 0),
    CONSTRAINT ck_farm_tiles_growth_stage CHECK (growth_stage BETWEEN 0 AND 3),
    CONSTRAINT ck_farm_tiles_nonnegative_coordinates CHECK (x >= 0 AND y >= 0),
    CONSTRAINT fk_farm_tiles_crop_item_code_item_definitions FOREIGN KEY(crop_item_code) REFERENCES item_definitions (item_code),
    CONSTRAINT fk_farm_tiles_world_id_player_worlds FOREIGN KEY(world_id) REFERENCES player_worlds (id) ON DELETE CASCADE,
    CONSTRAINT uq_farm_tiles_world_id UNIQUE (world_id, x, y)
);

CREATE INDEX ix_farm_tiles_crop_item_code ON farm_tiles (crop_item_code);

CREATE INDEX ix_farm_tiles_world_id ON farm_tiles (world_id);

INSERT INTO alembic_version (version_num) VALUES ('0001_initial_schema') RETURNING alembic_version.version_num;

-- Running upgrade 0001_initial_schema -> 0002_gameplay

CREATE TABLE fishing_spots (
    code VARCHAR(32) NOT NULL,
    name VARCHAR(64) NOT NULL,
    freezes_in_winter BOOLEAN DEFAULT false NOT NULL,
    CONSTRAINT pk_fishing_spots PRIMARY KEY (code)
);

CREATE TABLE goal_definitions (
    code VARCHAR(32) NOT NULL,
    kind VARCHAR(16) NOT NULL,
    title VARCHAR(128) NOT NULL,
    event VARCHAR(32) NOT NULL,
    target INTEGER NOT NULL,
    aura_reward INTEGER NOT NULL,
    CONSTRAINT pk_goal_definitions PRIMARY KEY (code),
    CONSTRAINT ck_goal_definitions_kind CHECK (kind IN ('achievement','daily')),
    CONSTRAINT ck_goal_definitions_goal_values CHECK (target > 0 AND aura_reward >= 0)
);

CREATE INDEX ix_goal_definitions_event ON goal_definitions (event);

CREATE TABLE house_tiers (
    tier SERIAL NOT NULL,
    name VARCHAR(64) NOT NULL,
    cost INTEGER NOT NULL,
    required_level INTEGER DEFAULT '1' NOT NULL,
    CONSTRAINT pk_house_tiers PRIMARY KEY (tier),
    CONSTRAINT ck_house_tiers_tier_values CHECK (tier >= 1 AND cost >= 0 AND required_level >= 1)
);

CREATE TABLE collection_entries (
    player_id INTEGER NOT NULL,
    item_code VARCHAR(32) NOT NULL,
    first_obtained_at TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
    CONSTRAINT pk_collection_entries PRIMARY KEY (player_id, item_code),
    CONSTRAINT fk_collection_entries_item_code_item_definitions FOREIGN KEY(item_code) REFERENCES item_definitions (item_code),
    CONSTRAINT fk_collection_entries_player_id_players FOREIGN KEY(player_id) REFERENCES players (id) ON DELETE CASCADE
);

CREATE TABLE decorations (
    id SERIAL NOT NULL,
    player_id INTEGER NOT NULL,
    item_code VARCHAR(32) NOT NULL,
    x INTEGER NOT NULL,
    y INTEGER NOT NULL,
    CONSTRAINT pk_decorations PRIMARY KEY (id),
    CONSTRAINT ck_decorations_coordinates CHECK (x BETWEEN 0 AND 32767 AND y BETWEEN 0 AND 32767),
    CONSTRAINT fk_decorations_item_code_item_definitions FOREIGN KEY(item_code) REFERENCES item_definitions (item_code),
    CONSTRAINT fk_decorations_player_id_players FOREIGN KEY(player_id) REFERENCES players (id) ON DELETE CASCADE,
    CONSTRAINT uq_decorations_player_id UNIQUE (player_id, x, y)
);

CREATE INDEX ix_decorations_player_id ON decorations (player_id);

CREATE TABLE direct_messages (
    id SERIAL NOT NULL,
    sender_id INTEGER NOT NULL,
    receiver_id INTEGER NOT NULL,
    body VARCHAR(500) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
    CONSTRAINT pk_direct_messages PRIMARY KEY (id),
    CONSTRAINT ck_direct_messages_not_self CHECK (sender_id <> receiver_id),
    CONSTRAINT fk_direct_messages_receiver_id_players FOREIGN KEY(receiver_id) REFERENCES players (id) ON DELETE CASCADE,
    CONSTRAINT fk_direct_messages_sender_id_players FOREIGN KEY(sender_id) REFERENCES players (id) ON DELETE CASCADE
);

CREATE INDEX ix_direct_messages_sender_id ON direct_messages (sender_id);

CREATE INDEX ix_dm_inbox ON direct_messages (receiver_id, id);

CREATE TABLE encounter_hints (
    player_id INTEGER NOT NULL,
    feature VARCHAR(32) NOT NULL,
    CONSTRAINT pk_encounter_hints PRIMARY KEY (player_id, feature),
    CONSTRAINT fk_encounter_hints_player_id_players FOREIGN KEY(player_id) REFERENCES players (id) ON DELETE CASCADE
);

CREATE TABLE feedback (
    id SERIAL NOT NULL,
    player_id INTEGER NOT NULL,
    message VARCHAR(2000) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
    CONSTRAINT pk_feedback PRIMARY KEY (id),
    CONSTRAINT fk_feedback_player_id_players FOREIGN KEY(player_id) REFERENCES players (id) ON DELETE CASCADE
);

CREATE INDEX ix_feedback_player_id ON feedback (player_id);

CREATE TABLE fishing_sessions (
    player_id INTEGER NOT NULL,
    cast_id VARCHAR(64) NOT NULL,
    spot_code VARCHAR(32) NOT NULL,
    rod_code VARCHAR(32) NOT NULL,
    item_code VARCHAR(32) NOT NULL,
    bite_at TIMESTAMP WITH TIME ZONE NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    resolved BOOLEAN DEFAULT false NOT NULL,
    CONSTRAINT pk_fishing_sessions PRIMARY KEY (player_id),
    CONSTRAINT ck_fishing_sessions_bite_window CHECK (expires_at > bite_at),
    CONSTRAINT fk_fishing_sessions_item_code_item_definitions FOREIGN KEY(item_code) REFERENCES item_definitions (item_code),
    CONSTRAINT fk_fishing_sessions_player_id_players FOREIGN KEY(player_id) REFERENCES players (id) ON DELETE CASCADE,
    CONSTRAINT fk_fishing_sessions_rod_code_item_definitions FOREIGN KEY(rod_code) REFERENCES item_definitions (item_code),
    CONSTRAINT fk_fishing_sessions_spot_code_fishing_spots FOREIGN KEY(spot_code) REFERENCES fishing_spots (code),
    CONSTRAINT uq_fishing_sessions_cast_id UNIQUE (cast_id)
);

CREATE TABLE friendships (
    low_id INTEGER NOT NULL,
    high_id INTEGER NOT NULL,
    requested_by INTEGER NOT NULL,
    status VARCHAR(16) DEFAULT 'pending' NOT NULL,
    CONSTRAINT pk_friendships PRIMARY KEY (low_id, high_id),
    CONSTRAINT ck_friendships_status CHECK (status IN ('pending','accepted')),
    CONSTRAINT ck_friendships_canonical_pair CHECK (low_id < high_id),
    CONSTRAINT ck_friendships_request_participant CHECK (requested_by = low_id OR requested_by = high_id),
    CONSTRAINT fk_friendships_high_id_players FOREIGN KEY(high_id) REFERENCES players (id) ON DELETE CASCADE,
    CONSTRAINT fk_friendships_low_id_players FOREIGN KEY(low_id) REFERENCES players (id) ON DELETE CASCADE,
    CONSTRAINT fk_friendships_requested_by_players FOREIGN KEY(requested_by) REFERENCES players (id) ON DELETE CASCADE
);

CREATE INDEX ix_friend_high_status ON friendships (high_id, status);

CREATE TABLE gifts (
    id SERIAL NOT NULL,
    sender_id INTEGER NOT NULL,
    receiver_id INTEGER NOT NULL,
    request_id VARCHAR(64) NOT NULL,
    item_code VARCHAR(32) NOT NULL,
    quantity INTEGER NOT NULL,
    claimed BOOLEAN DEFAULT false NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
    CONSTRAINT pk_gifts PRIMARY KEY (id),
    CONSTRAINT ck_gifts_gift_values CHECK (sender_id <> receiver_id AND quantity > 0),
    CONSTRAINT fk_gifts_item_code_item_definitions FOREIGN KEY(item_code) REFERENCES item_definitions (item_code),
    CONSTRAINT fk_gifts_receiver_id_players FOREIGN KEY(receiver_id) REFERENCES players (id) ON DELETE CASCADE,
    CONSTRAINT fk_gifts_sender_id_players FOREIGN KEY(sender_id) REFERENCES players (id) ON DELETE CASCADE,
    CONSTRAINT uq_gifts_sender_id UNIQUE (sender_id, request_id)
);

CREATE INDEX ix_gift_mailbox ON gifts (receiver_id, claimed, id);

CREATE TABLE goal_progress (
    player_id INTEGER NOT NULL,
    goal_code VARCHAR(32) NOT NULL,
    period INTEGER NOT NULL,
    progress INTEGER DEFAULT '0' NOT NULL,
    rewarded BOOLEAN DEFAULT false NOT NULL,
    CONSTRAINT pk_goal_progress PRIMARY KEY (player_id, goal_code, period),
    CONSTRAINT ck_goal_progress_progress CHECK (progress >= 0),
    CONSTRAINT fk_goal_progress_goal_code_goal_definitions FOREIGN KEY(goal_code) REFERENCES goal_definitions (code),
    CONSTRAINT fk_goal_progress_player_id_players FOREIGN KEY(player_id) REFERENCES players (id) ON DELETE CASCADE
);

CREATE TABLE ground_drops (
    id SERIAL NOT NULL,
    player_id INTEGER NOT NULL,
    item_code VARCHAR(32) NOT NULL,
    spot_code VARCHAR(32) NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    claimed BOOLEAN DEFAULT false NOT NULL,
    CONSTRAINT pk_ground_drops PRIMARY KEY (id),
    CONSTRAINT fk_ground_drops_item_code_item_definitions FOREIGN KEY(item_code) REFERENCES item_definitions (item_code),
    CONSTRAINT fk_ground_drops_player_id_players FOREIGN KEY(player_id) REFERENCES players (id) ON DELETE CASCADE,
    CONSTRAINT fk_ground_drops_spot_code_fishing_spots FOREIGN KEY(spot_code) REFERENCES fishing_spots (code)
);

CREATE INDEX ix_ground_owner_expiry ON ground_drops (player_id, expires_at);

CREATE TABLE item_rules (
    item_code VARCHAR(32) NOT NULL,
    partition VARCHAR(32) NOT NULL,
    required_level INTEGER DEFAULT '1' NOT NULL,
    harvest_code VARCHAR(32),
    pet_food BOOLEAN DEFAULT false NOT NULL,
    pet_accessory BOOLEAN DEFAULT false NOT NULL,
    fishing_rod BOOLEAN DEFAULT false NOT NULL,
    CONSTRAINT pk_item_rules PRIMARY KEY (item_code),
    CONSTRAINT ck_item_rules_partition CHECK (partition IN ('seeds','crops','fish','rare_materials','tools','houses')),
    CONSTRAINT ck_item_rules_level CHECK (required_level >= 1),
    CONSTRAINT fk_item_rules_harvest_code_item_definitions FOREIGN KEY(harvest_code) REFERENCES item_definitions (item_code),
    CONSTRAINT fk_item_rules_item_code_item_definitions FOREIGN KEY(item_code) REFERENCES item_definitions (item_code) ON DELETE CASCADE
);

CREATE TABLE login_streaks (
    player_id INTEGER NOT NULL,
    last_date DATE,
    streak INTEGER DEFAULT '0' NOT NULL,
    CONSTRAINT pk_login_streaks PRIMARY KEY (player_id),
    CONSTRAINT ck_login_streaks_streak CHECK (streak >= 0),
    CONSTRAINT fk_login_streaks_player_id_players FOREIGN KEY(player_id) REFERENCES players (id) ON DELETE CASCADE
);

CREATE TABLE notifications (
    id SERIAL NOT NULL,
    player_id INTEGER NOT NULL,
    kind VARCHAR(32) NOT NULL,
    message VARCHAR(512) NOT NULL,
    target VARCHAR(128),
    event_key VARCHAR(128),
    is_read BOOLEAN DEFAULT false NOT NULL,
    dismissed BOOLEAN DEFAULT false NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
    CONSTRAINT pk_notifications PRIMARY KEY (id),
    CONSTRAINT fk_notifications_player_id_players FOREIGN KEY(player_id) REFERENCES players (id) ON DELETE CASCADE,
    CONSTRAINT uq_notifications_player_id UNIQUE (player_id, event_key)
);

CREATE INDEX ix_notification_inbox ON notifications (player_id, dismissed, id);

CREATE TABLE player_blocks (
    player_id INTEGER NOT NULL,
    blocked_id INTEGER NOT NULL,
    CONSTRAINT pk_player_blocks PRIMARY KEY (player_id, blocked_id),
    CONSTRAINT ck_player_blocks_not_self CHECK (player_id <> blocked_id),
    CONSTRAINT fk_player_blocks_blocked_id_players FOREIGN KEY(blocked_id) REFERENCES players (id) ON DELETE CASCADE,
    CONSTRAINT fk_player_blocks_player_id_players FOREIGN KEY(player_id) REFERENCES players (id) ON DELETE CASCADE
);

CREATE INDEX ix_block_reverse ON player_blocks (blocked_id, player_id);

CREATE TABLE player_houses (
    player_id INTEGER NOT NULL,
    tier INTEGER DEFAULT '1' NOT NULL,
    CONSTRAINT pk_player_houses PRIMARY KEY (player_id),
    CONSTRAINT fk_player_houses_player_id_players FOREIGN KEY(player_id) REFERENCES players (id) ON DELETE CASCADE,
    CONSTRAINT fk_player_houses_tier_house_tiers FOREIGN KEY(tier) REFERENCES house_tiers (tier)
);

CREATE TABLE player_pets (
    player_id INTEGER NOT NULL,
    species VARCHAR(32) DEFAULT 'cat' NOT NULL,
    name VARCHAR(32) DEFAULT 'Mochi' NOT NULL,
    affection INTEGER DEFAULT '0' NOT NULL,
    accessory_code VARCHAR(32),
    last_interaction_at TIMESTAMP WITH TIME ZONE,
    fetch_started_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT pk_player_pets PRIMARY KEY (player_id),
    CONSTRAINT ck_player_pets_affection_range CHECK (affection BETWEEN 0 AND 100),
    CONSTRAINT fk_player_pets_accessory_code_item_definitions FOREIGN KEY(accessory_code) REFERENCES item_definitions (item_code),
    CONSTRAINT fk_player_pets_player_id_players FOREIGN KEY(player_id) REFERENCES players (id) ON DELETE CASCADE
);

CREATE TABLE player_profiles (
    player_id INTEGER NOT NULL,
    character_code VARCHAR(32),
    map_code VARCHAR(32) DEFAULT 'campus' NOT NULL,
    status_message VARCHAR(140) DEFAULT '' NOT NULL,
    water_charges INTEGER DEFAULT '20' NOT NULL,
    music_volume INTEGER DEFAULT '100' NOT NULL,
    effects_volume INTEGER DEFAULT '100' NOT NULL,
    fullscreen BOOLEAN DEFAULT false NOT NULL,
    tutorial_step INTEGER DEFAULT '0' NOT NULL,
    last_seen_at TIMESTAMP WITH TIME ZONE,
    last_saved_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT pk_player_profiles PRIMARY KEY (player_id),
    CONSTRAINT ck_player_profiles_volume_range CHECK (music_volume BETWEEN 0 AND 100 AND effects_volume BETWEEN 0 AND 100),
    CONSTRAINT ck_player_profiles_tutorial_range CHECK (tutorial_step BETWEEN 0 AND 3),
    CONSTRAINT ck_player_profiles_water_capacity CHECK (water_charges BETWEEN 0 AND 20),
    CONSTRAINT fk_player_profiles_player_id_players FOREIGN KEY(player_id) REFERENCES players (id) ON DELETE CASCADE
);

CREATE INDEX ix_player_profiles_last_seen_at ON player_profiles (last_seen_at);

CREATE TABLE player_reports (
    id SERIAL NOT NULL,
    reporter_id INTEGER NOT NULL,
    reported_id INTEGER NOT NULL,
    reason VARCHAR(32) NOT NULL,
    details VARCHAR(1000) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
    CONSTRAINT pk_player_reports PRIMARY KEY (id),
    CONSTRAINT ck_player_reports_not_self CHECK (reporter_id <> reported_id),
    CONSTRAINT fk_player_reports_reported_id_players FOREIGN KEY(reported_id) REFERENCES players (id) ON DELETE CASCADE,
    CONSTRAINT fk_player_reports_reporter_id_players FOREIGN KEY(reporter_id) REFERENCES players (id) ON DELETE CASCADE
);

CREATE INDEX ix_player_reports_reported_id ON player_reports (reported_id);

CREATE INDEX ix_player_reports_reporter_id ON player_reports (reporter_id);

CREATE TABLE player_statistics (
    player_id INTEGER NOT NULL,
    event VARCHAR(32) NOT NULL,
    value INTEGER DEFAULT '0' NOT NULL,
    CONSTRAINT pk_player_statistics PRIMARY KEY (player_id, event),
    CONSTRAINT ck_player_statistics_value CHECK (value >= 0),
    CONSTRAINT fk_player_statistics_player_id_players FOREIGN KEY(player_id) REFERENCES players (id) ON DELETE CASCADE
);

CREATE TABLE shop_purchases (
    player_id INTEGER NOT NULL,
    request_id VARCHAR(64) NOT NULL,
    item_code VARCHAR(32) NOT NULL,
    quantity INTEGER NOT NULL,
    unit_price INTEGER NOT NULL,
    game_day INTEGER NOT NULL,
    CONSTRAINT pk_shop_purchases PRIMARY KEY (player_id, request_id),
    CONSTRAINT ck_shop_purchases_purchase_values CHECK (quantity > 0 AND unit_price >= 0),
    CONSTRAINT fk_shop_purchases_item_code_item_definitions FOREIGN KEY(item_code) REFERENCES item_definitions (item_code),
    CONSTRAINT fk_shop_purchases_player_id_players FOREIGN KEY(player_id) REFERENCES players (id) ON DELETE CASCADE
);

CREATE INDEX ix_purchase_player_day ON shop_purchases (player_id, game_day);

CREATE TABLE trades (
    id SERIAL NOT NULL,
    sender_id INTEGER NOT NULL,
    receiver_id INTEGER NOT NULL,
    request_id VARCHAR(64) NOT NULL,
    offered_code VARCHAR(32) NOT NULL,
    offered_quantity INTEGER NOT NULL,
    wanted_code VARCHAR(32) NOT NULL,
    wanted_quantity INTEGER NOT NULL,
    status VARCHAR(16) DEFAULT 'pending' NOT NULL,
    CONSTRAINT pk_trades PRIMARY KEY (id),
    CONSTRAINT ck_trades_status CHECK (status IN ('pending','accepted','declined','cancelled')),
    CONSTRAINT ck_trades_trade_values CHECK (sender_id <> receiver_id AND offered_quantity > 0 AND wanted_quantity > 0),
    CONSTRAINT fk_trades_offered_code_item_definitions FOREIGN KEY(offered_code) REFERENCES item_definitions (item_code),
    CONSTRAINT fk_trades_receiver_id_players FOREIGN KEY(receiver_id) REFERENCES players (id) ON DELETE CASCADE,
    CONSTRAINT fk_trades_sender_id_players FOREIGN KEY(sender_id) REFERENCES players (id) ON DELETE CASCADE,
    CONSTRAINT fk_trades_wanted_code_item_definitions FOREIGN KEY(wanted_code) REFERENCES item_definitions (item_code),
    CONSTRAINT uq_trades_sender_id UNIQUE (sender_id, request_id)
);

CREATE INDEX ix_trade_receiver_status ON trades (receiver_id, status, id);

CREATE INDEX ix_trades_sender_id ON trades (sender_id);

CREATE TABLE world_events (
    code VARCHAR(64) NOT NULL,
    title VARCHAR(128) NOT NULL,
    starts_at TIMESTAMP WITH TIME ZONE NOT NULL,
    ends_at TIMESTAMP WITH TIME ZONE NOT NULL,
    item_code VARCHAR(32) NOT NULL,
    quantity INTEGER DEFAULT '1' NOT NULL,
    CONSTRAINT pk_world_events PRIMARY KEY (code),
    CONSTRAINT ck_world_events_event_values CHECK (ends_at > starts_at AND quantity > 0),
    CONSTRAINT fk_world_events_item_code_item_definitions FOREIGN KEY(item_code) REFERENCES item_definitions (item_code)
);

CREATE INDEX ix_event_window ON world_events (starts_at, ends_at);

CREATE TABLE event_claims (
    player_id INTEGER NOT NULL,
    event_code VARCHAR(64) NOT NULL,
    CONSTRAINT pk_event_claims PRIMARY KEY (player_id, event_code),
    CONSTRAINT fk_event_claims_event_code_world_events FOREIGN KEY(event_code) REFERENCES world_events (code) ON DELETE CASCADE,
    CONSTRAINT fk_event_claims_player_id_players FOREIGN KEY(player_id) REFERENCES players (id) ON DELETE CASCADE
);

CREATE TABLE social_invites (
    id SERIAL NOT NULL,
    sender_id INTEGER NOT NULL,
    receiver_id INTEGER NOT NULL,
    world_id INTEGER NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    accepted BOOLEAN DEFAULT false NOT NULL,
    CONSTRAINT pk_social_invites PRIMARY KEY (id),
    CONSTRAINT ck_social_invites_not_self CHECK (sender_id <> receiver_id),
    CONSTRAINT fk_social_invites_receiver_id_players FOREIGN KEY(receiver_id) REFERENCES players (id) ON DELETE CASCADE,
    CONSTRAINT fk_social_invites_sender_id_players FOREIGN KEY(sender_id) REFERENCES players (id) ON DELETE CASCADE,
    CONSTRAINT fk_social_invites_world_id_player_worlds FOREIGN KEY(world_id) REFERENCES player_worlds (id) ON DELETE CASCADE
);

CREATE INDEX ix_invite_receiver_expiry ON social_invites (receiver_id, expires_at);

CREATE INDEX ix_social_invites_sender_id ON social_invites (sender_id);

INSERT INTO house_tiers (tier, name, cost, required_level) VALUES (1, 'Starter House', 0, 1);

INSERT INTO player_profiles (player_id) SELECT id FROM players;

INSERT INTO player_houses (player_id, tier) SELECT id, 1 FROM players;

UPDATE alembic_version SET version_num='0002_gameplay' WHERE alembic_version.version_num = '0001_initial_schema';

-- Running upgrade 0002_gameplay -> 0003_presence

CREATE TABLE nearby_messages (
    id SERIAL NOT NULL,
    sender_id INTEGER NOT NULL,
    body VARCHAR(500) NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    CONSTRAINT pk_nearby_messages PRIMARY KEY (id),
    CONSTRAINT fk_nearby_messages_sender_id_players FOREIGN KEY(sender_id) REFERENCES players (id) ON DELETE CASCADE
);

CREATE INDEX ix_nearby_expiry ON nearby_messages (expires_at);

CREATE TABLE player_presence (
    player_id INTEGER NOT NULL,
    room VARCHAR(64) NOT NULL,
    x FLOAT NOT NULL,
    y FLOAT NOT NULL,
    sequence INTEGER DEFAULT '0' NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL,
    emote VARCHAR(16),
    emote_until TIMESTAMP WITH TIME ZONE,
    CONSTRAINT pk_player_presence PRIMARY KEY (player_id),
    CONSTRAINT ck_player_presence_sequence CHECK (sequence >= 0),
    CONSTRAINT fk_player_presence_player_id_players FOREIGN KEY(player_id) REFERENCES players (id) ON DELETE CASCADE
);

CREATE INDEX ix_presence_room_time ON player_presence (room, updated_at);

CREATE TABLE nearby_message_recipients (
    message_id INTEGER NOT NULL,
    player_id INTEGER NOT NULL,
    CONSTRAINT pk_nearby_message_recipients PRIMARY KEY (message_id, player_id),
    CONSTRAINT fk_nearby_message_recipients_message_id_nearby_messages FOREIGN KEY(message_id) REFERENCES nearby_messages (id) ON DELETE CASCADE,
    CONSTRAINT fk_nearby_message_recipients_player_id_players FOREIGN KEY(player_id) REFERENCES players (id) ON DELETE CASCADE
);

CREATE INDEX ix_nearby_message_recipients_player_id ON nearby_message_recipients (player_id);

UPDATE alembic_version SET version_num='0003_presence' WHERE alembic_version.version_num = '0002_gameplay';

-- Running upgrade 0003_presence -> 0004_boolean_defaults

ALTER TABLE fishing_spots ALTER COLUMN freezes_in_winter SET DEFAULT false;

ALTER TABLE fishing_sessions ALTER COLUMN resolved SET DEFAULT false;

ALTER TABLE ground_drops ALTER COLUMN claimed SET DEFAULT false;

ALTER TABLE gifts ALTER COLUMN claimed SET DEFAULT false;

ALTER TABLE goal_progress ALTER COLUMN rewarded SET DEFAULT false;

ALTER TABLE item_rules ALTER COLUMN pet_food SET DEFAULT false;

ALTER TABLE item_rules ALTER COLUMN pet_accessory SET DEFAULT false;

ALTER TABLE item_rules ALTER COLUMN fishing_rod SET DEFAULT false;

ALTER TABLE notifications ALTER COLUMN is_read SET DEFAULT false;

ALTER TABLE notifications ALTER COLUMN dismissed SET DEFAULT false;

ALTER TABLE player_profiles ALTER COLUMN fullscreen SET DEFAULT false;

ALTER TABLE social_invites ALTER COLUMN accepted SET DEFAULT false;

UPDATE alembic_version SET version_num='0004_boolean_defaults' WHERE alembic_version.version_num = '0003_presence';

COMMIT;
