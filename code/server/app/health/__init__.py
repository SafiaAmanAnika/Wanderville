"""Liveness and readiness probes.

These live outside ``app/modules/`` because they are not a game domain: they
expose process and database state to the orchestrator rather than implementing
any player-facing behaviour, and they must stay reachable even when a domain
module fails to import.
"""