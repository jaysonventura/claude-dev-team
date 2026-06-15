"""End-to-end tests for the login HTTP API.

Unlike ``test_login.py`` (which unit-tests ``AuthService``/``RateLimiter`` in
process with a fake clock), this module drives the *real* server over the wire:
it boots ``api.server.make_server`` on a real OS-assigned port, runs it in a
background thread, and exercises ``POST /login`` with genuine ``urllib`` HTTP
requests. It asserts the full user journey — success, bad credentials, unknown
user, lockout, and the no-validity-leak property — through HTTP status codes and
JSON bodies, the way a client actually sees the service.

Determinism / isolation:
  * Port 0 -> the kernel picks a free port; we read the real one back. No fixed
    ports, so parallel runs never collide.
  * The rate limiter is keyed on ``username|ip``; the client IP is overridable
    via the ``X-Real-IP`` header. Each test uses a *distinct* IP so lockout
    buckets never bleed across tests, regardless of run order.
  * The server is started fresh in ``setUp`` and fully torn down in ``tearDown``
    (``shutdown()`` then ``server_close()``) so no thread or socket leaks.

Python 3.9, standard library only: unittest + urllib + threading.
"""
from __future__ import annotations

import json
import threading
import unittest
import urllib.error
import urllib.request
from typing import Any, Dict, Optional, Tuple

from api.server import make_server

# Seeded fixture user and the limiter budget, per the API contract.
GOOD_USER = "alice"
GOOD_PASS = "correct horse battery"
MAX_ATTEMPTS = 3
# Generous timeout: PBKDF2 at the production iteration count can take a moment,
# but a hung request must never wedge the whole suite.
HTTP_TIMEOUT = 30.0


class LoginApiE2ETestCase(unittest.TestCase):
    """Base case that boots a real server per test and offers an HTTP helper."""

    def setUp(self) -> None:
        # Bind port 0 -> OS assigns a free port; read the real port back so the
        # client talks to exactly the server we started.
        self.server = make_server(host="127.0.0.1", port=0)
        self.port = self.server.server_address[1]
        self.base_url = "http://127.0.0.1:{}/login".format(self.port)
        self.thread = threading.Thread(
            target=self.server.serve_forever, name="e2e-login-server", daemon=True
        )
        self.thread.start()

    def tearDown(self) -> None:
        # Stop the serve loop, close the listening socket, join the thread so the
        # next test gets a clean slate and nothing leaks between tests.
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=HTTP_TIMEOUT)

    def post_login(
        self,
        username: str,
        password: str,
        ip: Optional[str] = None,
    ) -> Tuple[int, Dict[str, Any]]:
        """POST a JSON login over real HTTP; return (status_code, parsed_json).

        ``ip`` is sent as the ``X-Real-IP`` header so tests can pin the rate
        limiter bucket. Non-2xx responses raise ``HTTPError`` in urllib; we catch
        it and read the body so 401/429 are returned as ordinary results, not
        exceptions — that is exactly what an HTTP client must handle.
        """
        body = json.dumps({"username": username, "password": password}).encode("utf-8")
        request = urllib.request.Request(
            self.base_url,
            data=body,
            method="POST",
            headers={"Content-Type": "application/json"},
        )
        if ip is not None:
            request.add_header("X-Real-IP", ip)
        try:
            with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT) as response:
                status = response.getcode()
                payload = response.read()
        except urllib.error.HTTPError as http_error:
            # 401 / 429 land here; the JSON body still carries the reason.
            status = http_error.code
            payload = http_error.read()
        parsed = json.loads(payload.decode("utf-8")) if payload else {}
        return status, parsed


class SuccessfulLoginE2ETests(LoginApiE2ETestCase):
    def test_successful_login_returns_200_success_ok(self) -> None:
        # Journey step 1: valid credentials over the wire -> 200 + success True.
        status, body = self.post_login(GOOD_USER, GOOD_PASS, ip="203.0.113.1")
        self.assertEqual(status, 200)
        self.assertIs(body.get("success"), True)
        self.assertEqual(body.get("reason"), "ok")


class BadCredentialsE2ETests(LoginApiE2ETestCase):
    def test_wrong_password_returns_401_bad_credentials(self) -> None:
        # Journey step 2: right user, wrong password -> 401 bad_credentials.
        status, body = self.post_login(GOOD_USER, "wrong password", ip="203.0.113.2")
        self.assertEqual(status, 401)
        self.assertEqual(body.get("reason"), "bad_credentials")
        self.assertNotEqual(body.get("success"), True)

    def test_unknown_user_returns_401_bad_credentials(self) -> None:
        # Journey step 3: unknown user -> 401, and the *same* reason as a wrong
        # password so a client cannot enumerate which usernames exist.
        status, body = self.post_login("nobody", "whatever", ip="203.0.113.3")
        self.assertEqual(status, 401)
        self.assertEqual(body.get("reason"), "bad_credentials")
        self.assertNotEqual(body.get("success"), True)

    def test_unknown_user_indistinguishable_from_wrong_password(self) -> None:
        # Anti-enumeration over HTTP: wrong-password and unknown-user responses
        # must be identical in status and reason. Distinct IPs so neither path
        # consumes the other's lockout budget.
        wrong_status, wrong_body = self.post_login(
            GOOD_USER, "wrong password", ip="203.0.113.4"
        )
        unknown_status, unknown_body = self.post_login(
            "ghost", "wrong password", ip="203.0.113.5"
        )
        self.assertEqual(wrong_status, unknown_status)
        self.assertEqual(wrong_body.get("reason"), unknown_body.get("reason"))
        self.assertEqual(unknown_body.get("reason"), "bad_credentials")


class LockoutJourneyE2ETests(LoginApiE2ETestCase):
    def test_lockout_after_max_attempts_returns_429(self) -> None:
        # Journey step 4: from one IP, MAX_ATTEMPTS (3) wrong tries are each
        # answered 401 bad_credentials; the next request is rate-limited -> 429.
        ip = "198.51.100.10"
        for attempt in range(MAX_ATTEMPTS):
            status, body = self.post_login(GOOD_USER, "wrong password", ip=ip)
            self.assertEqual(
                status, 401, "attempt {} should be 401".format(attempt + 1)
            )
            self.assertEqual(body.get("reason"), "bad_credentials")
        # The 4th request exceeds the budget.
        locked_status, locked_body = self.post_login(GOOD_USER, "wrong password", ip=ip)
        self.assertEqual(locked_status, 429)
        self.assertEqual(locked_body.get("reason"), "rate_limited")
        self.assertNotEqual(locked_body.get("success"), True)

    def test_locked_out_correct_password_still_429_no_validity_leak(self) -> None:
        # Journey step 5: once a bucket is locked, even the CORRECT password is
        # refused with 429 rate_limited. The limiter runs before any credential
        # check, so a locked attacker learns nothing about password validity.
        ip = "198.51.100.20"
        for _ in range(MAX_ATTEMPTS):
            status, body = self.post_login(GOOD_USER, "wrong password", ip=ip)
            self.assertEqual(status, 401)
            self.assertEqual(body.get("reason"), "bad_credentials")
        # Correct password from the now-locked IP: still rate-limited, never 200.
        leak_status, leak_body = self.post_login(GOOD_USER, GOOD_PASS, ip=ip)
        self.assertEqual(leak_status, 429)
        self.assertEqual(leak_body.get("reason"), "rate_limited")
        self.assertNotEqual(leak_body.get("success"), True)


if __name__ == "__main__":
    unittest.main()
