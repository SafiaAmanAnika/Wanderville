# Core database relationships

All player-owned foreign keys cascade on deletion. Item definitions are reference
data and are not deleted with accounts. `world_state` is an independent singleton.

```mermaid
erDiagram
    players ||--o{ refresh_tokens : sessions
    players ||--o{ account_tokens : verification_reset
    players {
        int id PK
        string username UK
        string email UK
        int token_version
    }
    refresh_tokens {
        int player_id FK
        string token_hash UK
        datetime revoked_at
    }
    account_tokens {
        int player_id FK
        string token_hash UK
        string token_type
        datetime used_at
    }
```

```mermaid
erDiagram
    players ||--o| player_economy : balance
    players ||--o| player_experience : progression
    players ||--o{ economy_transactions : history
    player_economy {
        int player_id PK,FK
        bigint aura_balance
    }
    player_experience {
        int player_id PK,FK
        bigint total_xp
        int level
    }
    economy_transactions {
        int id PK
        int player_id FK
        bigint amount
        string reason
    }
```

```mermaid
erDiagram
    players ||--o| player_worlds : owns
    players ||--o{ inventory_items : inventory
    player_worlds ||--o{ farm_tiles : contains
    item_definitions ||--o{ inventory_items : defines
    item_definitions o|--o{ farm_tiles : crop
```

Signup requires the three one-to-one gameplay records in one transaction; the
database enforces at most one of each per player. Empty farm tiles have a null
crop reference. `(world_id, x, y)` is unique. Inventory stacks are unique by
`(player_id, item_code, location)`.
