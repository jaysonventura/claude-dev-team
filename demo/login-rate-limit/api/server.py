"""Minimal HTTP API exposing POST /login over the demo AuthService.

Standard library only (http.server, json). Python 3.9 compatible.

A single shared AuthService and RateLimiter are created per server via the
make_server factory so an end-to-end test can drive real login + rate-limit
behaviour over the wire.
"""
from __future__ import annotations

import json
from http.server import BaseHTTPRequestHandler, HTTPServer

from auth.login import AuthService, LoginReason, hash_password
from auth.rate_limit import RateLimiter

# Demo seed user. Low PBKDF2 iterations keep tests fast; this is a throwaway
# fixture credential, not a production secret.
_DEMO_USERNAME = "alice"
_DEMO_PASSWORD = "correct horse battery"
_DEMO_ITERATIONS = 1000

# Map each login outcome to its HTTP status code.
_STATUS_BY_REASON = {
    LoginReason.OK: 200,
    LoginReason.BAD_CREDENTIALS: 401,
    LoginReason.RATE_LIMITED: 429,
}

# Refuse to read absurdly large bodies into memory.
_MAX_BODY_BYTES = 64 * 1024


def _build_auth() -> AuthService:
    """Create the shared AuthService seeded with the demo user."""
    users = {
        _DEMO_USERNAME: hash_password(_DEMO_PASSWORD, iterations=_DEMO_ITERATIONS),
    }
    limiter = RateLimiter(max_attempts=3, window_seconds=60)
    return AuthService(users, limiter)


class _LoginHandler(BaseHTTPRequestHandler):
    """Handler for POST /login. The shared AuthService is injected as a
    class attribute by make_server (see ``auth`` below)."""

    # Populated by make_server with the per-server AuthService instance.
    auth: AuthService

    # Quieter logging; the default handler logs every request to stderr.
    def log_message(self, fmt: str, *args: object) -> None:  # noqa: A003
        return

    def _write_json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _client_ip(self) -> str:
        # Trust X-Real-IP when present (set by the test / a fronting proxy);
        # otherwise fall back to the socket peer address.
        real_ip = self.headers.get("X-Real-IP")
        if real_ip:
            return real_ip.strip()
        return self.client_address[0]

    def _read_json_body(self) -> dict:
        """Read and parse the request body as a JSON object.

        Raises ValueError on missing/oversized/invalid JSON or non-object
        payloads so the caller can return a clean 400 (never a 500).
        """
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except (TypeError, ValueError):
            raise ValueError("invalid Content-Length")
        if length < 0 or length > _MAX_BODY_BYTES:
            raise ValueError("invalid body length")
        raw = self.rfile.read(length) if length else b""
        if not raw:
            raise ValueError("empty body")
        try:
            data = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            raise ValueError("body is not valid JSON")
        if not isinstance(data, dict):
            raise ValueError("body must be a JSON object")
        return data

    def do_POST(self) -> None:  # noqa: N802 (http.server naming)
        if self.path != "/login":
            self._write_json(404, {"error": "not_found"})
            return

        try:
            data = self._read_json_body()
        except ValueError as exc:
            self._write_json(400, {"error": "bad_request", "detail": str(exc)})
            return

        username = data.get("username")
        password = data.get("password")
        if not isinstance(username, str) or not isinstance(password, str):
            self._write_json(
                400,
                {"error": "bad_request", "detail": "username and password required"},
            )
            return

        result = self.auth.login(username, password, self._client_ip())
        status = _STATUS_BY_REASON.get(result.reason, 400)
        self._write_json(
            status,
            {"success": result.success, "reason": result.reason.value},
        )

    def do_GET(self) -> None:  # noqa: N802
        self._write_json(404, {"error": "not_found"})


def make_server(host: str = "127.0.0.1", port: int = 0) -> HTTPServer:
    """Build an HTTPServer exposing POST /login backed by a fresh AuthService.

    With ``port=0`` the OS assigns a free port; read it from
    ``server.server_address[1]`` after construction.
    """
    auth = _build_auth()

    # Per-server handler subclass carrying this server's shared AuthService,
    # so concurrent servers in tests never share auth/rate-limit state.
    handler = type("_BoundLoginHandler", (_LoginHandler,), {"auth": auth})
    return HTTPServer((host, port), handler)


if __name__ == "__main__":
    server = make_server(port=8099)
    host, bound_port = server.server_address[0], server.server_address[1]
    print(f"serving demo login API on http://{host}:{bound_port}/login")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
