"""Transport seam — the client depends on no HTTP framework.

``HTTPTransport`` uses ``http.client`` from the standard library, so the client
adds no dependency to the package. A ``Transport`` is a ``Protocol``, so a test
can inject a fake.
"""

from __future__ import annotations

import http.client
import socket
import threading
from typing import Dict, List, Optional, Protocol
from urllib.parse import urlsplit

from .error import TransportError


class Transport(Protocol):
    """POST a JSON-RPC body and return the raw response body."""

    def post(self, body: str) -> str: ...


class HTTPTransport:
    """A keep-alive JSON-RPC transport with an explicit timeout.

    One connection is opened lazily and reused for every call, which is what a
    JSON-RPC client wants: the SDK's per-call overhead over a reusable
    connection was measured at ~0.18 ms against 0.356 ms median for a fresh
    connection per call — 2× on a call whose server-side work is a constant
    string (#140).

    Timeout: ``timeout`` is the socket timeout, so it bounds connect, send and
    every read, exactly as ``urlopen(timeout=…)`` did — a server that accepts
    the request and then stops writing still trips it. It is a per-operation
    bound, not a deadline for the whole exchange.

    Concurrency: one connection means one request on the wire at a time, so
    concurrent callers serialise on a lock instead of interleaving bytes on the
    socket. ``urlopen`` per call was incidentally thread-safe; a pool without a
    lock would not be, and a governed call's body is not something to interleave.

    Reconnect: a server is free to close an idle keep-alive connection, and
    "closed between calls" is not an answer. When a connection this transport
    has already used fails before a response line arrives, the connection is
    dropped and the request is sent once on a fresh one. The caveat is real and
    is stated rather than hidden: the body of the first attempt may have
    reached the server, so a retried *command* could in principle run twice.
    It is limited to exactly that case — a connection that had already served a
    call — because retrying a fresh connection's failure would hide a server
    that is genuinely refusing. A timeout is never retried: a hung server is
    not a stale socket.
    """

    def __init__(
        self,
        url: str,
        headers: Optional[Dict[str, str]] = None,
        timeout: float = 30.0,
    ) -> None:
        parts = urlsplit(url)
        if parts.scheme not in ("http", "https"):
            raise ValueError(
                f"transport: {url!r} is not http(s); the JSON-RPC endpoint is"
                " an http(s) URL"
            )
        if not parts.hostname:
            raise ValueError(f"transport: {url!r} names no host")
        self.url = url
        self.headers = dict(headers or {})
        self.timeout = timeout
        self._scheme = parts.scheme
        self._host = parts.hostname
        self._port = parts.port
        self._path = parts.path or "/"
        if parts.query:
            self._path = f"{self._path}?{parts.query}"
        self._connection: Optional[http.client.HTTPConnection] = None
        self._used = False
        # RLock: `post` retries through `_post_once` while holding it.
        self._lock = threading.RLock()

    # ── connection lifecycle ────────────────────────────────────────────────

    def _connect(self) -> "http.client.HTTPConnection":
        if self._connection is None:
            factory = (
                http.client.HTTPSConnection
                if self._scheme == "https"
                else http.client.HTTPConnection
            )
            self._connection = factory(self._host, self._port, timeout=self.timeout)
            self._used = False
        return self._connection

    def _drop(self) -> None:
        """Forget the connection; the next call opens a fresh one."""
        if self._connection is not None:
            try:
                self._connection.close()
            finally:
                self._connection = None
                self._used = False

    def close(self) -> None:
        """Close the pooled connection, if one is open."""
        self._drop()

    def __enter__(self) -> "HTTPTransport":
        return self

    def __exit__(self, *exc_info) -> None:
        self._drop()

    # ── the seam ───────────────────────────────────────────────────────────

    def post(self, body: str) -> str:
        payload = body.encode("utf-8")
        headers = {"content-type": "application/json", **self.headers}
        with self._lock:
            return self._post_locked(payload, headers)

    def _post_locked(self, payload: bytes, headers: Dict[str, str]) -> str:
        connection = self._connect()
        reusable = self._used
        try:
            connection.request("POST", self._path, body=payload, headers=headers)
            response = connection.getresponse()
            raw = response.read()
            status = response.status
        except (
            http.client.RemoteDisconnected,
            http.client.NotConnected,
            ConnectionResetError,
            BrokenPipeError,
        ) as exc:
            self._drop()
            if reusable:
                # The stale keep-alive case this class exists for: retry once,
                # on a connection the server has not closed yet.
                return self._post_once(payload, headers)
            raise TransportError(f"transport: {exc}") from exc
        except (socket.timeout, TimeoutError) as exc:
            self._drop()
            raise TransportError(f"transport: timeout after {self.timeout}s: {exc}") from exc
        except OSError as exc:
            self._drop()
            raise TransportError(f"transport: {exc}") from exc

        self._used = True
        if not 200 <= status < 300:
            # The host refused at the HTTP layer; it did not answer JSON-RPC.
            raise TransportError(f"transport: HTTP {status}")
        return raw.decode("utf-8")

    def _post_once(self, payload: bytes, headers: Dict[str, str]) -> str:
        """One attempt on a fresh connection, with no second retry."""
        connection = self._connect()
        try:
            connection.request("POST", self._path, body=payload, headers=headers)
            response = connection.getresponse()
            raw = response.read()
            status = response.status
        except (socket.timeout, TimeoutError) as exc:
            self._drop()
            raise TransportError(f"transport: timeout after {self.timeout}s: {exc}") from exc
        except (OSError, http.client.HTTPException) as exc:
            self._drop()
            raise TransportError(f"transport: {exc}") from exc

        self._used = True
        if not 200 <= status < 300:
            raise TransportError(f"transport: HTTP {status}")
        return raw.decode("utf-8")


class MockTransport:
    """A test transport that records requests and replays queued responses."""

    def __init__(self, responses: Optional[List[str]] = None) -> None:
        self.requests: List[str] = []
        self.responses: List[str] = list(responses or [])

    def post(self, body: str) -> str:
        self.requests.append(body)
        if not self.responses:
            raise TransportError("mock transport: no queued response")
        return self.responses.pop(0)