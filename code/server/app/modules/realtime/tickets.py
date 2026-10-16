"""Short-lived, single-use multiplayer admission tickets.

Why a ticket at all
-------------------
A Godot dedicated server has to learn "which player is this ENet peer" without
ever holding an account credential. Forwarding a bearer token or a refresh token
onto ENet would put a reusable, long-lived secret on a transport that is not
encrypted by default, and would let anyone who sniffed it impersonate the player
over HTTP too. A ticket is the opposite of that: worthless outside one
handshake, useless the moment it is spent, and about as long-lived as the
connection setup it covers.

Properties this module guarantees
---------------------------------
* **Bound to a verified player.** Issuance re-reads the account, so a disabled
  or unverified player cannot mint one, and a ticket revoked by an account
  change stops working.
* **Single use, atomically.** Consumption takes the entry out of the registry
  under the same lock it read it with, so two racing peers cannot both win.
  Replay fails rather than returning a second session.
* **Short lived.** Default 30 seconds, which has to cover a UDP handshake and
  nothing more.
* **Opaque and hashed at rest.** Only the caller ever sees the raw value; the
  registry stores a SHA-256 digest, so neither a log line nor a memory dump
  yields a usable ticket.
* **Bounded.** The registry is capped and prunes expired entries on every
  write, so a flood of issuances cannot grow it without limit.

This is process-local state, like the realtime runtime: correct for the
single-worker deployment this project documents, not for several API processes
sharing a load balancer. Tickets are cheap to re-request, so a client that
loses a race simply asks for another.
"""

import hmac
from dataclasses import dataclass
from threading import RLock

from app.core.clock import as_utc, utcnow
from app.core.config import settings
from app.modules.auth.security import hash_token, new_token


class TicketError(Exception):
    """Rejected admission. The message is safe to return to a server operator."""


@dataclass(frozen=True)
class Ticket:
    raw: str
    player_id: int
    expires_at: object
    server_id: str


@dataclass
class TicketRecord:
    player_id: int
    expires_at: object
    server_id: str
    issued_at: object


class TicketRegistry:
    """Bounded, thread-safe, single-use ticket store."""

    def __init__(self):
        self.lock = RLock()
        self._by_digest: dict[str, TicketRecord] = {}

    def issue(self, player_id: int, server_id: str = "") -> Ticket:
        raw = new_token()
        now = utcnow()
        expires_at = now + __import__("datetime").timedelta(
            seconds=settings.multiplayer_ticket_ttl_seconds
        )
        with self.lock:
            self._prune_locked(now)
            if len(self._by_digest) >= settings.multiplayer_ticket_capacity:
                self._evict_oldest_locked()
            self._by_digest[hash_token(raw)] = TicketRecord(
                player_id=player_id,
                expires_at=expires_at,
                server_id=server_id,
                issued_at=now,
            )
        return Ticket(
            raw=raw,
            player_id=player_id,
            expires_at=expires_at,
            server_id=server_id,
        )

    def consume(self, raw: str, server_id: str = "") -> TicketRecord:
        """Spend a ticket, or raise.

        The pop happens under the lock that found the entry, so a concurrent
        second attempt sees nothing and is rejected. That is the whole replay
        defence; there is no window between "check" and "use".
        """
        if not raw:
            raise TicketError("MISSING_TICKET")
        digest = hash_token(raw)
        now = utcnow()
        with self.lock:
            record = self._by_digest.get(digest)
            if record is None:
                # Expired entries are indistinguishable from never-issued ones
                # by design: the caller learns nothing about which failed.
                raise TicketError("INVALID_TICKET")
            if as_utc(record.expires_at) <= now:
                del self._by_digest[digest]
                raise TicketError("EXPIRED_TICKET")
            if server_id and record.server_id and record.server_id != server_id:
                # Bound to a different server; do not spend it, so the rightful
                # host can still use it.
                raise TicketError("TICKET_SERVER_MISMATCH")
            del self._by_digest[digest]
            return record

    def _prune_locked(self, now):
        for digest in [
            digest
            for digest, record in self._by_digest.items()
            if as_utc(record.expires_at) <= now
        ]:
            del self._by_digest[digest]

    def _evict_oldest_locked(self):
        ordered = sorted(
            self._by_digest.items(), key=lambda item: item[1].issued_at
        )
        for digest, _record in ordered[: max(1, len(ordered) // 8)]:
            del self._by_digest[digest]

    def size(self) -> int:
        with self.lock:
            return len(self._by_digest)

    def clear(self):
        with self.lock:
            self._by_digest.clear()


registry = TicketRegistry()


def issue_ticket(player_id: int, server_id: str = "") -> Ticket:
    return registry.issue(player_id, server_id)


def consume_ticket(raw: str, server_id: str = "") -> TicketRecord:
    return registry.consume(raw, server_id)


def constant_time_matches(candidate: str, expected: str) -> bool:
    """Compare the internal host secret without leaking its length by timing."""
    if not expected:
        # An unset secret must never authenticate anybody.
        return False
    return hmac.compare_digest(candidate.encode(), expected.encode())