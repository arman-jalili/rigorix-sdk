"""Client error taxonomy.

``RpcError`` is the host refusing (a JSON-RPC ``error`` object); the code and
data survive. ``TransportError`` is the host not answering (network, timeout,
non-2xx). ``ProtocolError`` is a malformed/answer-less response.
"""

from __future__ import annotations

from typing import Any, Optional


class ClientError(Exception):
    """Base class for every client-side failure."""


class TransportError(ClientError):
    """The transport failed: network/IO, timeout, or a non-2xx response."""


class ProtocolError(ClientError):
    """A malformed JSON-RPC response, or one that is not an answer."""


class RpcError(ClientError):
    """A JSON-RPC ``error`` object; ``code`` and ``data`` are preserved."""

    def __init__(self, code: int, message: str, data: Any = None) -> None:
        super().__init__(f"json-rpc error {code}: {message}")
        self.code = code
        self.message = message
        self.data = data

    @property
    def rule_id(self) -> Optional[str]:
        """``data.rule_id`` when the host supplied one."""
        if isinstance(self.data, dict):
            value = self.data.get("rule_id")
            return value if isinstance(value, str) else None
        return None

    @property
    def step(self) -> Optional[str]:
        """``data.step`` when the host supplied one."""
        if isinstance(self.data, dict):
            value = self.data.get("step")
            return value if isinstance(value, str) else None
        return None


class IncompatibleVersion(ClientError):
    """The server's ``api_version`` major is not the one this client speaks."""

    def __init__(self, server: str, client_major: int) -> None:
        super().__init__(
            f"server apiVersion {server} is incompatible with the client "
            f"constraint (major {client_major})"
        )
        self.server = server
        self.client_major = client_major
