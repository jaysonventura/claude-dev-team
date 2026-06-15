"""Unit tests for the rate-limited login module.

Tests encode the architect's interface contract (TDD mindset):

    from auth.rate_limit import RateLimiter
    from auth.login import (AuthService, LoginReason, LoginResult,
                            StoredCredential, hash_password, verify_password)

These tests are deterministic: the only time source is an injected fake clock,
there is no network/filesystem/threading, and password fixtures use a low
iteration count (1000) so the suite runs fast. Python 3.9, stdlib unittest only.
"""
from __future__ import annotations

import unittest

from auth.login import (
    AuthService,
    LoginReason,
    LoginResult,
    StoredCredential,
    hash_password,
    verify_password,
)
from auth.rate_limit import RateLimiter


# Low iterations: keep the KDF cheap so tests stay fast. Never the 600k default.
FAST_ITERATIONS = 1000


class FakeClock:
    """A mutable, deterministic monotonic clock.

    Callable so it can be passed wherever a ``clock`` of ``time.monotonic`` type
    is expected. Time only moves when the test advances it -- no wall-clock or
    ordering flakiness.
    """

    def __init__(self, start: float = 1000.0) -> None:
        # The current time is held in a one-element list so the closure / callable
        # shares a single mutable cell (matches the "list-held float" contract).
        self._now = [float(start)]

    def __call__(self) -> float:
        return self._now[0]

    def advance(self, seconds: float) -> None:
        self._now[0] += float(seconds)


def build_users() -> dict:
    """Two users with deliberately low KDF iterations for speed."""
    return {
        "alice": hash_password("correct horse", iterations=FAST_ITERATIONS),
        "bob": hash_password("hunter2", iterations=FAST_ITERATIONS),
    }


class HashPasswordTests(unittest.TestCase):
    def test_hash_password_returns_stored_credential(self) -> None:
        cred = hash_password("pw", iterations=FAST_ITERATIONS)
        self.assertIsInstance(cred, StoredCredential)

    def test_same_password_yields_distinct_salts(self) -> None:
        # No deterministic hashing: a random salt per call means different output.
        a = hash_password("pw", iterations=FAST_ITERATIONS)
        b = hash_password("pw", iterations=FAST_ITERATIONS)
        self.assertNotEqual(a, b)

    def test_explicit_salt_is_reproducible(self) -> None:
        salt = b"\x00" * 16
        a = hash_password("pw", salt=salt, iterations=FAST_ITERATIONS)
        b = hash_password("pw", salt=salt, iterations=FAST_ITERATIONS)
        self.assertEqual(a, b)


class VerifyPasswordTests(unittest.TestCase):
    def test_verify_password_true_for_correct(self) -> None:
        cred = hash_password("s3cret", iterations=FAST_ITERATIONS)
        self.assertTrue(verify_password("s3cret", cred))

    def test_verify_password_false_for_wrong(self) -> None:
        cred = hash_password("s3cret", iterations=FAST_ITERATIONS)
        self.assertFalse(verify_password("nope", cred))


class LoginSuccessTests(unittest.TestCase):
    def setUp(self) -> None:
        self.clock = FakeClock()
        self.limiter = RateLimiter(max_attempts=5, window_seconds=60.0, clock=self.clock)
        self.service = AuthService(build_users(), limiter=self.limiter)

    def test_correct_credentials_succeed(self) -> None:
        # Case 1: correct user + password -> success, OK.
        result = self.service.login("alice", "correct horse", "10.0.0.1")
        self.assertIsInstance(result, LoginResult)
        self.assertIs(result.success, True)
        self.assertIs(result.reason, LoginReason.OK)

    def test_success_does_not_consume_lockout_budget(self) -> None:
        # Repeated good logins must never trip the limiter.
        for _ in range(10):
            result = self.service.login("alice", "correct horse", "10.0.0.1")
            self.assertIs(result.success, True)
            self.assertIs(result.reason, LoginReason.OK)


class LoginFailureTests(unittest.TestCase):
    def setUp(self) -> None:
        self.clock = FakeClock()
        self.limiter = RateLimiter(max_attempts=5, window_seconds=60.0, clock=self.clock)
        self.service = AuthService(build_users(), limiter=self.limiter)

    def test_wrong_password_is_bad_credentials(self) -> None:
        # Case 2.
        result = self.service.login("alice", "wrong", "10.0.0.1")
        self.assertIs(result.success, False)
        self.assertIs(result.reason, LoginReason.BAD_CREDENTIALS)

    def test_unknown_user_is_bad_credentials(self) -> None:
        # Case 3.
        result = self.service.login("ghost", "whatever", "10.0.0.1")
        self.assertIs(result.success, False)
        self.assertIs(result.reason, LoginReason.BAD_CREDENTIALS)

    def test_unknown_user_indistinguishable_from_wrong_password(self) -> None:
        # Case 3 (anti-enumeration): both paths return the identical result so an
        # attacker cannot tell whether the username exists.
        wrong_pw = self.service.login("alice", "wrong", "10.0.0.1")
        unknown = self.service.login("ghost", "wrong", "10.0.0.2")
        self.assertEqual(
            (wrong_pw.success, wrong_pw.reason),
            (unknown.success, unknown.reason),
        )
        self.assertIs(unknown.reason, LoginReason.BAD_CREDENTIALS)


class LockoutTests(unittest.TestCase):
    def setUp(self) -> None:
        self.clock = FakeClock()
        self.limiter = RateLimiter(max_attempts=5, window_seconds=60.0, clock=self.clock)
        self.service = AuthService(build_users(), limiter=self.limiter)

    def test_lockout_after_max_attempts(self) -> None:
        # Case 4: 5 denied logins for the same username|ip, then RATE_LIMITED.
        for _ in range(5):
            result = self.service.login("alice", "wrong", "10.0.0.1")
            self.assertIs(result.reason, LoginReason.BAD_CREDENTIALS)
        locked = self.service.login("alice", "wrong", "10.0.0.1")
        self.assertIs(locked.success, False)
        self.assertIs(locked.reason, LoginReason.RATE_LIMITED)

    def test_lockout_is_keyed_per_username_and_ip(self) -> None:
        # Exhausting the budget for one key must not lock a different key.
        for _ in range(5):
            self.service.login("alice", "wrong", "10.0.0.1")
        # Same user, different IP -> still merely bad credentials, not locked.
        other_ip = self.service.login("alice", "wrong", "10.0.0.99")
        self.assertIs(other_ip.reason, LoginReason.BAD_CREDENTIALS)

    def test_no_validity_leak_when_rate_limited(self) -> None:
        # Case 6: once locked out, even the CORRECT password is rejected as
        # RATE_LIMITED -- the limiter must run before credential checking so a
        # locked attacker learns nothing about password validity.
        for _ in range(5):
            self.service.login("alice", "wrong", "10.0.0.1")
        locked = self.service.login("alice", "correct horse", "10.0.0.1")
        self.assertIs(locked.success, False)
        self.assertIs(locked.reason, LoginReason.RATE_LIMITED)


class WindowResetTests(unittest.TestCase):
    def setUp(self) -> None:
        self.clock = FakeClock()
        self.limiter = RateLimiter(max_attempts=5, window_seconds=60.0, clock=self.clock)
        self.service = AuthService(build_users(), limiter=self.limiter)

    def test_window_reset_allows_again(self) -> None:
        # Case 5: advance the fake clock past window_seconds -> key allowed again.
        for _ in range(5):
            self.service.login("alice", "wrong", "10.0.0.1")
        self.assertIs(
            self.service.login("alice", "wrong", "10.0.0.1").reason,
            LoginReason.RATE_LIMITED,
        )

        # Move just past the 60s window so the recorded attempts age out.
        self.clock.advance(60.1)

        # Correct password should now actually succeed.
        result = self.service.login("alice", "correct horse", "10.0.0.1")
        self.assertIs(result.success, True)
        self.assertIs(result.reason, LoginReason.OK)

    def test_window_not_reset_before_expiry(self) -> None:
        # Just under the window: still locked (boundary check).
        for _ in range(5):
            self.service.login("alice", "wrong", "10.0.0.1")
        self.clock.advance(59.0)
        still_locked = self.service.login("alice", "correct horse", "10.0.0.1")
        self.assertIs(still_locked.reason, LoginReason.RATE_LIMITED)


class RateLimiterUnitTests(unittest.TestCase):
    """Direct tests of RateLimiter independent of AuthService."""

    def setUp(self) -> None:
        self.clock = FakeClock()
        self.limiter = RateLimiter(max_attempts=3, window_seconds=30.0, clock=self.clock)

    def test_check_allows_up_to_max_then_blocks(self) -> None:
        key = "alice|10.0.0.1"
        self.assertTrue(self.limiter.check(key))
        self.assertTrue(self.limiter.check(key))
        self.assertTrue(self.limiter.check(key))
        # 4th call within the window is blocked.
        self.assertFalse(self.limiter.check(key))

    def test_remaining_counts_down(self) -> None:
        key = "alice|10.0.0.1"
        self.assertEqual(self.limiter.remaining(key), 3)
        self.limiter.check(key)
        self.assertEqual(self.limiter.remaining(key), 2)
        self.limiter.check(key)
        self.limiter.check(key)
        self.assertEqual(self.limiter.remaining(key), 0)

    def test_reset_clears_key(self) -> None:
        key = "alice|10.0.0.1"
        for _ in range(3):
            self.limiter.check(key)
        self.assertFalse(self.limiter.check(key))
        self.limiter.reset(key)
        self.assertTrue(self.limiter.check(key))

    def test_window_expiry_frees_attempts(self) -> None:
        key = "alice|10.0.0.1"
        for _ in range(3):
            self.limiter.check(key)
        self.assertFalse(self.limiter.check(key))
        self.clock.advance(30.1)
        self.assertTrue(self.limiter.check(key))

    def test_keys_are_independent(self) -> None:
        for _ in range(3):
            self.limiter.check("alice|10.0.0.1")
        self.assertFalse(self.limiter.check("alice|10.0.0.1"))
        # A different key is unaffected.
        self.assertTrue(self.limiter.check("bob|10.0.0.1"))


if __name__ == "__main__":
    unittest.main()
