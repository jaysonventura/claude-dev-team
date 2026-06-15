"""Password hashing and rate-limited authentication (standard library only)."""
from __future__ import annotations

import enum
import hashlib
import hmac
import secrets
from dataclasses import dataclass, field
from typing import Dict, Optional

from auth.rate_limit import RateLimiter

PBKDF2_HASH_NAME = "sha256"
PBKDF2_ITERATIONS = 600_000
SALT_BYTES = 16


class LoginReason(str, enum.Enum):
    OK = "ok"
    BAD_CREDENTIALS = "bad_credentials"
    RATE_LIMITED = "rate_limited"


@dataclass(frozen=True)
class LoginResult:
    success: bool
    reason: LoginReason


@dataclass(frozen=True)
class StoredCredential:
    salt: bytes = field(repr=False)
    dk: bytes = field(repr=False)
    iterations: int = PBKDF2_ITERATIONS

    def __repr__(self) -> str:  # never expose secret bytes
        return f"StoredCredential(iterations={self.iterations})"


def _pbkdf2(password: str, salt: bytes, iterations: int) -> bytes:
    return hashlib.pbkdf2_hmac(
        PBKDF2_HASH_NAME, password.encode("utf-8"), salt, iterations
    )


def hash_password(
    password: str,
    *,
    salt: Optional[bytes] = None,
    iterations: int = PBKDF2_ITERATIONS,
) -> StoredCredential:
    """Derive a PBKDF2-HMAC-SHA256 credential. Salt is random per call."""
    if iterations < 1:
        raise ValueError("iterations must be >= 1")
    if salt is None:
        salt = secrets.token_bytes(SALT_BYTES)
    dk = _pbkdf2(password, salt, iterations)
    return StoredCredential(salt=salt, dk=dk, iterations=iterations)


def verify_password(password: str, cred: StoredCredential) -> bool:
    """Constant-time verification against a stored credential."""
    candidate = _pbkdf2(password, cred.salt, cred.iterations)
    return hmac.compare_digest(candidate, cred.dk)


# Module-level fixed dummy credential used for unknown users so that the
# unknown-user path performs the same PBKDF2 work as a real user (no timing
# or branching difference that could enable username enumeration).
_DUMMY_CRED = hash_password(
    "dummy-password-for-timing-equalization",
    salt=b"\x00" * SALT_BYTES,
    iterations=PBKDF2_ITERATIONS,
)


class AuthService:
    def __init__(
        self,
        users: Dict[str, StoredCredential],
        limiter: Optional[RateLimiter] = None,
    ) -> None:
        # Copy so external mutation of the caller's dict cannot affect auth.
        self._users: Dict[str, StoredCredential] = dict(users)
        self._limiter = limiter if limiter is not None else RateLimiter()

    def login(self, username: str, password: str, ip: str) -> LoginResult:
        # 1. Rate limit fires FIRST; on deny do not touch the password store.
        #    Keyed per username+ip as the contract specifies. The same key is
        #    used consistently for the deny check and the success reset below.
        key = f"{username}|{ip}"
        if not self._limiter.check(key):
            return LoginResult(success=False, reason=LoginReason.RATE_LIMITED)

        # 2. Always run PBKDF2 (real or dummy) so unknown users are
        #    indistinguishable from wrong-password users.
        cred = self._users.get(username)
        if cred is None:
            verify_password(password, _DUMMY_CRED)
            return LoginResult(success=False, reason=LoginReason.BAD_CREDENTIALS)

        if verify_password(password, cred):
            # A success must not consume lockout budget: clear the window for
            # this key so repeated good logins never trip the limiter.
            self._limiter.reset(key)
            return LoginResult(success=True, reason=LoginReason.OK)
        return LoginResult(success=False, reason=LoginReason.BAD_CREDENTIALS)
