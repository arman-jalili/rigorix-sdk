"""Protocol client for the frozen ``rigorix.*`` JSON-RPC catalog."""

from __future__ import annotations

from .client import BatchCall, Client
from .error import (
    ClientError,
    CommandMayHaveExecuted,
    IncompatibleVersion,
    ProtocolError,
    RpcError,
    TransportError,
)
from .transport import HTTPTransport, MockTransport, Transport

__all__ = [
    "BatchCall",
    "Client",
    "ClientError",
    "CommandMayHaveExecuted",
    "HTTPTransport",
    "IncompatibleVersion",
    "MockTransport",
    "ProtocolError",
    "RpcError",
    "Transport",
    "TransportError",
]
