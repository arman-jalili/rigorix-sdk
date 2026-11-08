"""JSON-RPC 2.0 framing: single requests, batch arrays, notifications."""

from __future__ import annotations

import json
from typing import Any, Dict, List

from .error import ProtocolError

RpcId = Any  # int or str


def call(request_id: RpcId, method: str, params: Any = None) -> Dict[str, Any]:
    """A request expecting a response."""
    request: Dict[str, Any] = {"jsonrpc": "2.0", "method": method, "id": request_id}
    if params is not None:
        request["params"] = params
    return request


def notification(method: str, params: Any = None) -> Dict[str, Any]:
    """A notification: no ``id``, no response expected."""
    request: Dict[str, Any] = {"jsonrpc": "2.0", "method": method}
    if params is not None:
        request["params"] = params
    return request


def encode(request: Any) -> str:
    return json.dumps(request, separators=(",", ":"))


def encode_batch(requests: List[Dict[str, Any]]) -> str:
    return json.dumps(requests, separators=(",", ":"))


def decode(body: str) -> Dict[str, Any]:
    try:
        value = json.loads(body)
    except json.JSONDecodeError as exc:
        raise ProtocolError(f"invalid JSON-RPC response: {exc}") from exc
    if not isinstance(value, dict):
        raise ProtocolError("JSON-RPC response is not an object")
    return value


def decode_batch(body: str) -> List[Dict[str, Any]]:
    try:
        value = json.loads(body)
    except json.JSONDecodeError as exc:
        raise ProtocolError(f"invalid JSON-RPC batch response: {exc}") from exc
    if not isinstance(value, list) or not all(isinstance(item, dict) for item in value):
        raise ProtocolError("JSON-RPC batch response is not an array of objects")
    return value
