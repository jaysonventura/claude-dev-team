"""Sliding-window in-memory rate limiter (standard library only)."""
from __future__ import annotations

import time
from collections import deque
from typing import Callable, Deque, Dict


class RateLimiter:
    """Fixed-count sliding-window limiter keyed by an arbitrary string.

    Allows at most ``max_attempts`` recorded attempts per ``key`` within any
    ``window_seconds`` interval. The clock is injectable for deterministic
    tests; it must return a monotonically non-decreasing float (seconds).
    """

    def __init__(
        self,
        max_attempts: int = 5,
        window_seconds: float = 60.0,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        if max_attempts < 1:
            raise ValueError("max_attempts must be >= 1")
        if window_seconds <= 0:
            raise ValueError("window_seconds must be > 0")
        self._max_attempts = max_attempts
        self._window_seconds = float(window_seconds)
        self._clock = clock
        self._hits: Dict[str, Deque[float]] = {}

    def _prune(self, key: str, now: float) -> Deque[float]:
        """Drop timestamps older than the window; return the live deque."""
        hits = self._hits.get(key)
        if hits is None:
            hits = deque()
            self._hits[key] = hits
        cutoff = now - self._window_seconds
        while hits and hits[0] <= cutoff:
            hits.popleft()
        return hits

    def check(self, key: str) -> bool:
        """Prune expired attempts, record this attempt, return allow/deny.

        Returns True if the attempt is within the limit (and records it),
        False if recording it would exceed ``max_attempts`` (not recorded).
        """
        now = self._clock()
        hits = self._prune(key, now)
        if len(hits) >= self._max_attempts:
            return False
        hits.append(now)
        return True

    def remaining(self, key: str) -> int:
        """Attempts still allowed in the current window. Does NOT record."""
        now = self._clock()
        hits = self._prune(key, now)
        return max(0, self._max_attempts - len(hits))

    def reset(self, key: str) -> None:
        """Clear all recorded attempts for ``key``."""
        self._hits.pop(key, None)
