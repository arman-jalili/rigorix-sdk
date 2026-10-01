"""Canonical envelope bytes — byte-exact with the Rust engine + verifier.

The canonical form is ``serde_json::to_string(envelope with signature=None)``
as produced by rigorix-oss: **struct field order**, ``skip_serializing_if``
fields omitted when ``None``/empty, non-skipped ``Option`` fields emitted as
``null``, map-typed fields (``scoring_results`` and each result's
``dimensions``) with **sorted keys**, and ``serde_json::Value`` payloads with
sorted keys (the default ``serde_json`` map). The field order is read from
``schemas/envelope.json`` (its ``properties`` order mirrors the struct).

Getting this wrong makes the HMAC fail; the shared fixtures prove parity.
"""

from __future__ import annotations

import hashlib
import json
from functools import lru_cache
from typing import Any

from .corpus import schema_text

# ``Option`` fields with ``skip_serializing_if = "Option::is_none"``.
_SKIP_NONE = {
    "identity",
    "effect_key",
    "producer_id",
    "sequence",
    "prev_hash",
    "history_integrity",
    "history_policy",
    "anchor_head",
    "decision_context_ref",
    "payload",
}

# Vec/Map fields with ``skip_serializing_if = "Vec::is_empty"`` / map is_empty.
_SKIP_EMPTY = {
    "file_paths",
    "scoring_results",
    "approval_events",
    "scope_violations",
    "sequence_policy_findings",
    "requirement_findings",
    "precondition_findings",
}

# field -> ``$defs`` struct name (the value is a struct, or an array of them).
_NESTED = {
    "identity": "identityRef",
    "events": "executionEventRef",
    "approval_events": "approvalRecordRef",
    "scope_violations": "scopeViolationRef",
    "sequence_policy_findings": "sequencePolicyFindingRef",
    "requirement_findings": "requirementFindingRef",
    "precondition_findings": "preconditionFindingRef",
    "scoring_results": "scoringResultRef",
}


@lru_cache(maxsize=None)
def _order(def_name: str | None) -> tuple[str, ...]:
    schema = json.loads(schema_text("envelope.json"))
    if def_name is None:
        return tuple(schema["properties"].keys())
    return tuple(schema["$defs"][def_name]["properties"].keys())


def _sort_value(value: Any) -> Any:
    """Recursively sort object keys — ``serde_json::Value`` maps are sorted."""
    if isinstance(value, dict):
        return {key: _sort_value(value[key]) for key in sorted(value)}
    if isinstance(value, list):
        return [_sort_value(item) for item in value]
    return value


def _canonicalize(obj: dict, fields: tuple[str, ...]) -> dict:
    out: dict[str, Any] = {}
    for field in fields:
        if field not in obj:
            continue
        value = obj[field]
        if value is None and field in _SKIP_NONE:
            continue
        if isinstance(value, (list, dict)) and len(value) == 0 and field in _SKIP_EMPTY:
            continue
        if field == "signature":
            out[field] = None
        elif field == "payload":
            out[field] = _sort_value(value)
        elif field in _NESTED:
            out[field] = _canonicalize_nested(field, value, _NESTED[field])
        else:
            out[field] = value
    return out


def _canonicalize_nested(field: str, value: Any, def_name: str) -> Any:
    if field == "scoring_results":
        result: dict[str, Any] = {}
        for key in sorted(value):
            entry = _canonicalize(value[key], _order("scoringResultRef"))
            dimensions = entry.get("dimensions")
            if isinstance(dimensions, dict):
                entry["dimensions"] = {
                    name: _canonicalize(dimensions[name], _order("scoreDimensionRef"))
                    for name in sorted(dimensions)
                }
            result[key] = entry
        return result
    if isinstance(value, list):
        return [_canonicalize(item, _order(def_name)) for item in value]
    return _canonicalize(value, _order(def_name))


def canonical_bytes(envelope: dict | str) -> bytes:
    """Return the canonical envelope bytes (``signature`` nulled)."""
    if isinstance(envelope, str):
        envelope = json.loads(envelope)
    ordered = _canonicalize(envelope, _order(None))
    return json.dumps(ordered, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def envelope_hash(envelope: dict | str) -> str:
    """SHA-256 (hex) of the canonical bytes — the ``prev_hash`` value."""
    return hashlib.sha256(canonical_bytes(envelope)).hexdigest()
