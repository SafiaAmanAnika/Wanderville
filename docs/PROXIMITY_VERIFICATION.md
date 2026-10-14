# Proximity social verification — 14 October 2026

Validated with Python 3.12.10, Godot 4.6.2 and an isolated PostgreSQL 18 cluster.
The final client checks ran after merging origin/umeNdanish at f8be768 into diza.

| Check | Result |
| --- | --- |
| SQLite backend suite | 256 passed; 13 PostgreSQL-only cases skipped |
| Isolated PostgreSQL backend suite | 269 passed, including concurrent gifts and complete migration upgrade/downgrade |
| Native Godot social, two accounts | Alice and Bob passed with zero failed checks |
| Rendered native Godot social | Both accounts passed; prompt and gift confirmation screenshots reviewed |
| Existing Godot HUD + process restart | Both runs passed |
| Existing full-world two-client integration after merge | Alice and Bob passed with zero failed checks |
| Ruff and Git whitespace checks | Passed |
| Staged credential/artifact scan | Passed; .env and its backup remain ignored |

The native checks cover real WebSocket authentication and acknowledgements,
friend proximity prompts, speech bubbles, muted voice join, actual synthetic PCM
transport, native wishlist editing, gift confirmation, loss of a committed gift
response, persisted request recovery, inbox claiming and disconnect cleanup.
The full-world checks cover movement, nearby/private chat, reconnect, crops,
visits, guest removal, blocking and logout. Reconnection deliberately clears
nearby history from the previous room epoch instead of replaying it.

Artifacts remain local under code/server/.verification:

- client_cf08e7a9: final native social test after merge.
- client_54c69167: rendered native UI and screenshots.
- client_1369e95a: existing HUD and restart tests.
- client_87777ea8: final full-world tests after merge.
- postgres_30ebe6d1: PostgreSQL cluster/setup artifacts from the successful suite.

Two integration defects caught and fixed were float-valued Godot JSON IDs on
saved gift retries and the older farm-visiting migration's PostgreSQL boolean
conversion on downgrade. Test settings now isolate voice/media/worker options
from the developer's .env.

Physical microphone permissions, capture quality and a two-device conversation
have not been manually verified. The native transport uses uncompressed PCM over
WebSockets and has no echo cancellation; see [setup and limitations](PROXIMITY_BACKEND.md).
Full-world runs still emit existing map/atlas warnings and an ObjectDB cleanup
warning at exit; their assertions pass. No remote database migration or hosting
deployment was performed. Apply migration 0008_proximity_social before starting
the updated backend against an existing database.
