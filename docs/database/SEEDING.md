# Reference seeding

From `code/server`, after `python -m alembic upgrade head`:

```powershell
python -m app.db.seed
```

`app/db/catalog.json` contains the 22 original item definitions. Crop duration,
season, sell value, rarity and XP rewards are retained. Missing definitions are
inserted; known definition fields are updated by item_code. Unrelated custom
items are preserved. Repeated runs do not duplicate items or reset the global
environment clock.

The seed also creates `world_state` row 1 if absent: summer, clear weather,
seven-day season duration, forty-minute day/night cycle. These are the original
backend defaults. Player accounts, inventories and crops are not seed data.

| Group | Codes |
| --- | --- |
| General crops | paddy, wheat, sugarcane, corn, cotton |
| Summer crops | sweet_corn, bell_pepper, green_bean |
| Autumn crops | pumpkin, apple, turnip |
| Winter crops | potato, carrot, cabbage, strawberry |
| Spring crops | lettuce, pea, radish |
| Rare plants | moonflower, rivermint, sunbloom, ancient_grain |

To add a definition, add a unique item_code (at most 32 characters), name,
category, nonnegative values, positive growth_time_seconds for plants, season,
and xp_reward to the JSON. Valid plant categories are `*_crop` and `rare_plant`.
Run the seed intentionally and add relevant domain tests. The server does not
infer definitions from Godot assets. Coordinate balancing changes with the team;
changing duration while crops are active affects their remaining progression.

Reference updates are maintenance operations, not concurrently executed API
requests. Run a single seed process during setup/deployment. No request or
application startup performs seeding.
