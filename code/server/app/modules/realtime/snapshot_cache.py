"""Bounded passive snapshot reuse for the existing single-process server.

No authorization is shared between players. Every committed ORM write invalidates
all connection projections, including HTTP actions. A one-second maximum covers
external database edits and time-based changes; JWT expiry is checked on every
reuse. Voice policy leases are never extended by a cached read.
"""

from copy import deepcopy
from datetime import datetime
from threading import RLock
from time import monotonic

from app.core.clock import as_utc, utcnow
from app.core.config import settings
from app.modules.auth.security import decode_access_token
from app.modules.realtime.runtime import runtime


class SnapshotRevision:
    def __init__(self):
        self.lock = RLock()
        self.value = 0

    def current(self):
        with self.lock:
            return self.value

    def invalidate(self):
        with self.lock:
            self.value += 1


snapshot_revision = SnapshotRevision()


class SnapshotCache:
    def __init__(self):
        self.clear()

    def clear(self):
        self.packet = None
        self.until = 0
        self.key = None
        self.revision = None
        self.policy_revision = None

    @staticmethod
    def eligible(message):
        return (
            message.get("type", "snapshot") in ("snapshot", "heartbeat")
            and "request_id" not in message
            and isinstance(message.get("data", {}), dict)
        )

    def get(self, token, protocol, generation):
        if (
            self.packet is None
            or self.key != (token, protocol, generation)
            or monotonic() >= self.until
            or self.revision != snapshot_revision.current()
            or self.policy_revision != runtime.policy_revision()
        ):
            return None
        pid, _version = decode_access_token(token)
        packet = deepcopy(self.packet)
        if protocol == 2:
            # This checks connection ownership and returns live voice controls,
            # without calling apply() and renewing a stale authorization lease.
            state = runtime.view(pid, generation)
            packet["data"]["voice"] = state["voice"]
            packet["data"]["proximity"]["nearby"] = state["nearby"]
        packet["data"]["server_time"] = utcnow().isoformat()
        return packet

    def store(self, packet, token, protocol, generation, revision, policy_revision):
        self.clear()
        if (
            packet.get("type") != "snapshot"
            or revision != snapshot_revision.current()
            or policy_revision != runtime.policy_revision()
        ):
            return
        ttl = settings.realtime_snapshot_cache_seconds
        now = utcnow()
        data = packet["data"]
        # Do not retain expired chat, emotes or presence until the next TTL.
        for message in data.get("messages", []):
            ttl = min(ttl, self._remaining(message.get("expires_at"), now))
        for player in data.get("players", []):
            ttl = min(ttl, self._remaining(player.get("updated_at"), now)
                      + settings.presence_ttl_seconds)
            if player.get("emote") and player.get("emote_until"):
                ttl = min(ttl, self._remaining(player["emote_until"], now))
        if ttl <= 0:
            return
        self.key = (token, protocol, generation)
        self.revision = revision
        self.policy_revision = policy_revision
        self.until = monotonic() + ttl
        self.packet = deepcopy(packet)

    @staticmethod
    def _remaining(value, now):
        if value is None:
            return 0
        stamp = datetime.fromisoformat(value) if isinstance(value, str) else value
        return (as_utc(stamp) - now).total_seconds()
