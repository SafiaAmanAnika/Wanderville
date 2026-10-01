from collections import OrderedDict, deque
from threading import Lock
from time import monotonic

from fastapi import Request

from app.core.exceptions import AppError


class RateLimiter:
    """Bounded, process-local limiter. Use one worker or shared storage."""

    def __init__(self):
        self.buckets = OrderedDict()
        self.lock = Lock()

    def check(self, key: str, limit: int, window: int = 60):
        now = monotonic()
        with self.lock:
            hits = self.buckets.setdefault(key, deque())
            while hits and hits[0] <= now - window:
                hits.popleft()
            self.buckets.move_to_end(key)
            if len(hits) >= limit:
                raise AppError(
                    "RATE_LIMITED", "Too many attempts. Try again shortly.", 429
                )
            hits.append(now)
            if len(self.buckets) > 10000:
                self.buckets.popitem(last=False)

    def clear(self):
        with self.lock:
            self.buckets.clear()


limiter = RateLimiter()


def rate_limit(limit: int):
    def dependency(request: Request):
        ip = request.client.host if request.client else "unknown"
        limiter.check(f"{request.url.path}:{ip}", limit)

    return dependency
