"""Transport seam — the client depends on no HTTP framework.

``HTTPTransport`` uses ``urllib.request`` from the standard library, so the
client adds no dependency to the package. A ``Transport`` is a ``Protocol``, so
a test can inject a fake.
"""

from __future__ import annotations

import socket
import urllib.error
import urllib.request
from typing import Dict, List, Optional, Protocol

from .error import TransportError


class Transport(Protocol):
    """POST a JSON-RPC body and return the raw response body."""

    def post(self, body: str) -> str: ...


class HTTPTransport:
    """A ``urllib.request`` transport with an explicit timeout."""

    def __init__(
        self,
        url: str,
        headers: Optional[Dict[str, str]] = None,
        timeout: float = 30.0,
    ) -> None:
        self.url = url
        self.headers = dict(headers or {})
        self.timeout = timeout

    def post(self, body: str) -> str:
        request = urllib.request.Request(
            self.url,
            data=body.encode("utf-8"),
            headers={"content-type": "application/json", **self.headers},
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                return response.read().decode("utf-8")
        except urllib.error.HTTPError as exc:
            # The host refused at the HTTP layer; it did not answer JSON-RPC.
            raise TransportError(f"transport: HTTP {exc.code}") from exc
        except (urllib.error.URLError, socket.timeout, TimeoutError) as exc:
            raise TransportError(f"transport: {exc}") from exc


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
