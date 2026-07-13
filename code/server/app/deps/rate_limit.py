from __future__ import annotations

import os
import time
from collections import defaultdict
from typing import Callable
from functools import wraps

from fastapi import HTTPException, Request


class RateLimiter:
    """Simple in-memory sliding-window rate limiter."""

    def __init__(self) -> None:
        self._requests: dict[str, list[float]] = defaultdict(list)

    def is_allowed(self, key: str, max_requests: int, window_seconds: int) -> bool:
        now = time.time()
        cutoff = now - window_seconds
        self._requests[key] = [t for t in self._requests[key] if t > cutoff]
        if len(self._requests[key]) >= max_requests:
            return False
        self._requests[key].append(now)
        return True

    def reset(self) -> None:
        self._requests.clear()


rate_limiter = RateLimiter()

_RATE_LIMIT_DISABLED = os.environ.get("DISABLE_RATE_LIMIT", "").lower() in ("1", "true", "yes")


def _check_rate_limit(request: Request, max_requests: int) -> None:
    if _RATE_LIMIT_DISABLED:
        return
    client_ip = request.client.host if request.client else "unknown"
    key = f"{request.url.path}:{client_ip}"
    if not rate_limiter.is_allowed(key, max_requests, 60):
        raise HTTPException(
            status_code=429,
            detail={
                "success": False,
                "error": "RATE_LIMITED",
                "message": f"Too many requests. Limit: {max_requests} per 60s",
            },
        )


def rate_limit(max_requests: int, window_seconds: int = 60) -> Callable:
    """Decorator that applies rate limiting based on client IP."""

    def decorator(func: Callable) -> Callable:
        @wraps(func)
        def wrapper(*args, **kwargs):
            if _RATE_LIMIT_DISABLED:
                return func(*args, **kwargs)
            request: Request | None = kwargs.get("request")
            if request is None:
                for v in kwargs.values():
                    if isinstance(v, Request):
                        request = v
                        break
            client_ip = request.client.host if request and request.client else "unknown"
            key = f"{func.__name__}:{client_ip}"
            if not rate_limiter.is_allowed(key, max_requests, window_seconds):
                raise HTTPException(
                    status_code=429,
                    detail={
                        "success": False,
                        "error": "RATE_LIMITED",
                        "message": f"Too many requests. Limit: {max_requests} per {window_seconds}s",
                    },
                )
            return func(*args, **kwargs)

        return wrapper

    return decorator
