"""Single-worker ephemeral control plane. No client-supplied position grants audio.

All methods are protected because SQL work runs in threads and media runs in the
async event loop. Each audio frame checks two fresh control/policy leases.
"""

from dataclasses import dataclass, field
from threading import RLock
from time import monotonic
from uuid import uuid4
from app.core.config import settings
from app.core.exceptions import AppError

LEASE_SECONDS = 2.0


@dataclass
class Connection:
    generation: str
    last_control: float
    room: str = ""
    epoch: int = -1
    policy_until: float = 0
    peers: dict = field(default_factory=dict)
    privacy: str = "off"
    prompts: bool = True
    encounters: dict = field(default_factory=dict)
    voice_id: str | None = None
    muted: bool = True
    deafened: bool = False
    muted_players: set = field(default_factory=set)


class RealtimeRuntime:
    def __init__(self, clock=monotonic):
        self.clock = clock
        self.lock = RLock()
        self.connections = {}
        self.revision = 0

    def attach(self, pid):
        with self.lock:
            generation = str(uuid4())
            self.connections[pid] = Connection(generation, self.clock())
            self.revision += 1
            return generation

    def connection(self, pid, generation):
        row = self.connections.get(pid)
        if row is None or row.generation != generation:
            raise AppError("CONNECTION_REPLACED", "Connect again", 409)
        return row

    def detach(self, pid, generation):
        with self.lock:
            row = self.connections.get(pid)
            if row and row.generation == generation:
                del self.connections[pid]
                self.revision += 1

    def heartbeat(self, pid, generation):
        with self.lock:
            row = self.connection(pid, generation)
            if self.clock() - row.last_control > LEASE_SECONDS:
                row.voice_id = None
                row.muted = True
            row.last_control = self.clock()

    def invalidate(self, players, leave=False):
        with self.lock:
            self.revision += 1
            for pid, row in self.connections.items():
                if pid in players:
                    row.policy_until = 0
                    if leave:
                        row.voice_id = None
                for other in players:
                    row.peers.pop(other, None)

    def policy_revision(self):
        with self.lock:
            return self.revision

    def apply(self, pid, generation, revision, view):
        with self.lock:
            row = self.connection(pid, generation)
            if revision != self.revision:
                return False
            if (row.room, row.epoch) != (view["room"], view["room_epoch"]):
                row.voice_id = None
                row.encounters.clear()
                row.muted_players.clear()
            row.room, row.epoch = view["room"], view["room_epoch"]
            row.privacy = view["voice_privacy"]
            row.prompts = view["proximity_prompts"]
            row.peers = {peer["player_id"]: peer for peer in view["nearby"]}
            row.policy_until = self.clock() + LEASE_SECONDS
            if row.privacy == "off":
                row.voice_id = None
            now = self.clock()
            for other, encounter in list(row.encounters.items()):
                peer = row.peers.get(other)
                if peer is None or not peer["friend"]:
                    if encounter["outside_since"] is None:
                        encounter["outside_since"] = now
                    if (
                        now - encounter["outside_since"] >= 2
                        and now - encounter["opened_at"] >= 30
                    ):
                        del row.encounters[other]
                else:
                    encounter["outside_since"] = None
            for other, peer in row.peers.items():
                if peer["friend"] and peer["can_text"] and other not in row.encounters:
                    row.encounters[other] = dict(
                        id=str(uuid4()),
                        dismissed=False,
                        opened_at=now,
                        outside_since=None,
                    )
            return True

    def dismiss(self, pid, generation, target):
        with self.lock:
            encounter = self.connection(pid, generation).encounters.get(target)
            if encounter:
                encounter["dismissed"] = True

    def view(self, pid, generation):
        with self.lock:
            row = self.connection(pid, generation)
            if self.clock() - row.last_control > LEASE_SECONDS:
                row.voice_id = None
                row.muted = True
            peers = []
            if row.policy_until > self.clock():
                for other, peer in row.peers.items():
                    encounter = row.encounters.get(other)
                    peers.append(
                        {
                            **peer,
                            "encounter_id": encounter["id"] if encounter else None,
                            "show_prompt": bool(
                                row.prompts
                                and encounter
                                and not encounter["dismissed"]
                                and peer["friend"]
                            ),
                        }
                    )
            return {
                "room": row.room,
                "room_epoch": row.epoch,
                "nearby": peers,
                "voice": {
                    "session_id": row.voice_id,
                    "joined": row.voice_id is not None,
                    "muted": row.muted,
                    "deafened": row.deafened,
                    "muted_players": sorted(row.muted_players),
                },
            }

    def join(self, pid, generation):
        with self.lock:
            row = self.connection(pid, generation)
            if not settings.voice_enabled:
                raise AppError(
                    "VOICE_DISABLED", "Voice is not enabled on this server", 503
                )
            if row.policy_until <= self.clock() or row.privacy == "off":
                raise AppError(
                    "VOICE_PERMISSION_DENIED",
                    "Voice is unavailable for this session",
                    403,
                )
            if row.voice_id:
                return row.voice_id
            active = [c for c in self.connections.values() if c.voice_id]
            if (
                len(active) >= settings.voice_total_limit
                or sum(c.room == row.room for c in active) >= settings.voice_room_limit
            ):
                raise AppError("VOICE_ROOM_FULL", "Voice capacity reached", 409)
            row.voice_id = str(uuid4())
            row.muted, row.deafened = True, False
            return row.voice_id

    def leave(self, pid, generation):
        with self.lock:
            row = self.connection(pid, generation)
            row.voice_id = None
            row.muted = True

    def state(self, pid, generation, session_id, muted, deafened, muted_players):
        with self.lock:
            row = self.connection(pid, generation)
            if row.voice_id is None or row.voice_id != session_id:
                raise AppError("VOICE_SESSION_EXPIRED", "Join voice again", 409)
            row.muted, row.deafened = muted or deafened, deafened
            row.muted_players = set(muted_players)

    def connection_valid(self, pid, generation, session_id):
        with self.lock:
            row = self.connections.get(pid)
            return bool(
                row
                and row.generation == generation
                and row.voice_id == session_id
                and self.clock() - row.last_control <= LEASE_SECONDS
            )

    def media_valid(self, pid, generation, session_id):
        with self.lock:
            row = self.connections.get(pid)
            return bool(
                row
                and row.generation == generation
                and row.voice_id == session_id
                and self.clock() - row.last_control <= LEASE_SECONDS
                and row.policy_until > self.clock()
            )

    def audible(self, source, listener):
        with self.lock:
            a, b = self.connections.get(source), self.connections.get(listener)
            now = self.clock()
            if not a or not b or source == listener or not a.voice_id or not b.voice_id:
                return 0.0
            if any(
                c.policy_until <= now or now - c.last_control > LEASE_SECONDS
                for c in (a, b)
            ):
                return 0.0
            if (
                a.room != b.room
                or a.muted
                or a.deafened
                or b.deafened
                or source in b.muted_players
            ):
                return 0.0
            forward, reverse = a.peers.get(listener), b.peers.get(source)
            if (
                not forward
                or not reverse
                or not forward["can_voice"]
                or not reverse["can_voice"]
            ):
                return 0.0
            distance = max(forward["distance"], reverse["distance"])
            full = settings.proximity_radius * 0.25
            return max(
                0.0,
                min(
                    1.0,
                    (settings.proximity_radius - distance)
                    / (settings.proximity_radius - full),
                ),
            )

    def clear(self):
        with self.lock:
            self.connections.clear()
            self.revision += 1


runtime = RealtimeRuntime()
