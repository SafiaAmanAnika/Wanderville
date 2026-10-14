"""Which socket currently owns a player's realtime connection.

A player may hold only one realtime socket. When a new connection authenticates
it *replaces* the previous one, and the replaced socket must not be able to keep
mutating state on its successor's behalf.

That guarantee needs two properties a plain module-level ``dict`` did not have:

* **Atomicity.** Ownership is read from the event loop while an async media task
  may be running, so claim/check/release are guarded by a lock.
* **No stale entries.** ``release`` only clears the entry if the caller still
  owns it, so an evicted socket cannot delete the entry belonging to its
  successor. Entries are therefore bounded by the number of connected players.

The token compared here is the per-connection ``object()`` identity the socket
handler allocates, not the ``generation`` string used for voice leases: the two
answer different questions (socket ownership versus media authorization).
"""

from threading import RLock


class SocketRegistry:
    def __init__(self):
        self._lock = RLock()
        self._owners = {}

    def claim(self, pid, owner):
        """Make ``owner`` the sole socket for ``pid``, evicting any predecessor."""
        with self._lock:
            self._owners[pid] = owner
            return self._owners[pid]

    def owns(self, pid, owner):
        """Whether ``owner`` is still the current socket for ``pid``."""
        with self._lock:
            return self._owners.get(pid) is owner

    def release(self, pid, owner):
        """Drop the entry, but only if ``owner`` still holds it.

        Returns whether anything was removed, so a caller can tell the difference
        between a clean teardown and an already-evicted socket.
        """
        with self._lock:
            if self._owners.get(pid) is not owner:
                return False
            del self._owners[pid]
            return True

    def clear(self):
        with self._lock:
            self._owners.clear()

    def __len__(self):
        with self._lock:
            return len(self._owners)


sockets = SocketRegistry()